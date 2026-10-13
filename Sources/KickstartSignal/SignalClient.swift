//
// SignalClient.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import KickstartShared
import OSLog

/// An opt-in Signal client with independent application sessions.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
final class SignalClient {
    /// Performs one HTTP request and returns its response body and status code.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    private let apiKey: String
    private let bundleID: String
    private let transport: Transport
    private let identities: SignalIdentityStore
    private let appTransaction: @Sendable () async throws -> String
    private var verified: SignalVerifiedSession?
    private var verificationTask: Task<SignalVerifiedSession, Error>?

    private static let session = makeSession()

    #if DEBUG
    private static let logger = Logger(subsystem: "tools.kickstart.signal", category: "Transport")
    #endif

    /// Creates an ephemeral session with caching, cookies, and redirects disabled.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: SignalRedirectDelegate(), delegateQueue: nil)
    }

    /// Use the same app API key as Exchange. No work starts until an API method is called.
    convenience init(apiKey: String) {
        self.init(
            apiKey: apiKey,
            identities: SignalIdentityStore(),
            appTransaction: SignalAppTransactionEvidence.current
        ) { request in
            let (data, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw SignalError.invalidResponse }
            return (data, response.statusCode)
        }
    }

    /// Creates a client with injectable identity storage, app verification evidence, and transport.
    init(
        apiKey: String,
        identities: SignalIdentityStore,
        appTransaction: @escaping @Sendable () async throws -> String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        transport: @escaping Transport
    ) {
        self.bundleID = bundleID
        self.apiKey = apiKey
        self.identities = identities
        self.transport = transport
        self.appTransaction = appTransaction
    }

    /// Fetches the board settings and content limits, verifying the app session when needed.
    @discardableResult
    func loadConfiguration() async throws -> SignalConfiguration {
        try await send(path: "config")
    }

    /// Fetches one page ordered by most votes, optionally restricted to a single status.
    /// Equal vote counts fall back to newest creation order. Pass the returned cursor to continue the same query.
    func listRequests(
        status: SignalStatus? = nil,
        cursor: String? = nil,
        limit: Int = 100
    ) async throws -> SignalRequestPage {
        var query = [
            URLQueryItem(name: "sort", value: "votes"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let status {
            query.append(URLQueryItem(name: "status", value: status.rawValue))
        }

        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try await send(path: "requests", query: query)
    }

    /// Submitting a request also casts the installation's first vote for it.
    /// Keep the same idempotency key when retrying the same submission after a connection failure.
    func createRequest(
        title: String,
        description: String,
        isPremium: Bool = false,
        idempotencyKey: UUID = UUID()
    ) async throws -> SignalSubmission {
        var payload: [String: Any] = ["anonymous_id": identities.identity(), "title": title, "description": description]

        if isPremium {
            payload["is_premium"] = true
        }

        let submission: SignalSubmission = try await send(
            path: "requests",
            method: "POST",
            body: payload,
            idempotencyKey: idempotencyKey
        )

        if let hasVoted = submission.hasVoted {
            identities.setVote(hasVoted, requestID: submission.id)
        }

        return submission
    }

    /// Adds this installation's vote and saves it locally after the server confirms success.
    @discardableResult
    func vote(
        requestID: String,
        isPremium: Bool = false
    ) async throws -> SignalRequest {
        try validateID(requestID, prefix: "ksreq_")
        var payload: [String: Any] = ["anonymous_id": identities.identity()]

        if isPremium {
            payload["is_premium"] = true
        }

        let request: SignalRequest = try await send(path: "requests/\(requestID)/votes", method: "POST", body: payload)
        identities.setVote(true, requestID: requestID)

        return request
    }

    /// Removes this installation's vote and clears its local record after server confirmation.
    @discardableResult
    func removeVote(requestID: String) async throws -> SignalRequest {
        try validateID(requestID, prefix: "ksreq_")

        let request: SignalRequest = try await send(
            path: "requests/\(requestID)/votes",
            method: "DELETE",
            body: ["anonymous_id": identities.identity()]
        )
        identities.setVote(false, requestID: requestID)

        return request
    }

    /// Reads this installation's saved vote without networking or app verification.
    func hasVoted(requestID: String) -> Bool {
        identities.votedIDs().contains(requestID)
    }

    /// Fetches one page of published comments and developer replies for a request.
    func listComments(
        requestID: String,
        cursor: String? = nil,
        limit: Int = 100
    ) async throws -> SignalCommentPage {
        try validateID(requestID, prefix: "ksreq_")

        var query = [URLQueryItem(name: "limit", value: String(limit))]

        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try await send(path: "requests/\(requestID)/comments", query: query)
    }

    /// Submits a comment using this installation's anonymous identity.
    /// Reuse the idempotency key when retrying an unchanged comment after a connection failure.
    func createComment(
        requestID: String,
        body: String,
        isPremium: Bool = false,
        idempotencyKey: UUID = UUID()
    ) async throws -> SignalSubmission {
        try validateID(requestID, prefix: "ksreq_")

        var payload: [String: Any] = ["anonymous_id": identities.identity(), "body": body]

        if isPremium {
            payload["is_premium"] = true
        }

        return try await send(
            path: "requests/\(requestID)/comments",
            method: "POST",
            body: payload,
            idempotencyKey: idempotencyKey
        )
    }

    /// Reuses an unexpired session or shares one in-flight verification task between callers.
    /// App transaction evidence is fetched only when the server requests it.
    private func verifiedSession() async throws -> SignalVerifiedSession {
        if let verified, verified.expiresAt > .now {
            return verified
        }

        if let verificationTask {
            return try await verificationTask.value
        }

        let task = Task { @MainActor in
            let data: Data

            do {
                data = try await perform(
                    path: "sessions",
                    method: "POST",
                    body: ["bundle_id": bundleID, "sdk_version": kickstartSDKVersion],
                    authenticating: true
                )
            } catch is SignalVerificationRequired {
                let evidence = try await appTransaction()
                data = try await perform(
                    path: "sessions",
                    method: "POST",
                    body: ["bundle_id": bundleID, "sdk_version": kickstartSDKVersion, "app_transaction": evidence],
                    authenticating: true
                )
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            guard let response = try? decoder.decode(SignalSessionResponse.self, from: data),
                  response.sessionToken.hasPrefix("kss_"),
                  response.expiresIn > 0 else {
                throw SignalError.invalidResponse
            }

            return SignalVerifiedSession(
                token: response.sessionToken,
                expiresAt: .now.addingTimeInterval(
                    TimeInterval(max(0, response.expiresIn - 30))
                )
            )
        }

        verificationTask = task
        defer { verificationTask = nil }

        let session = try await task.value
        verified = session

        return session
    }

    /// Rejects malformed resource identifiers before they can be used in a URL path.
    private func validateID(_ value: String, prefix: String) throws {
        guard value.hasPrefix(prefix), value.count == prefix.count + 32,
              value.dropFirst(prefix.count).allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw SignalError.notFound
        }
    }

    /// Whether the configured key has the expected app API key format.
    private var hasValidAPIKey: Bool {
        apiKey.hasPrefix("ks_live_") && apiKey.count == 51 && apiKey.dropFirst(8).allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        }
    }

    /// Sends a verified request and decodes its JSON, mapping decoding failures to an invalid response.
    private func send<Value: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        idempotencyKey: UUID? = nil
    ) async throws -> Value {
        let data = try await perform(
            path: path,
            method: method,
            query: query,
            body: body,
            idempotencyKey: idempotencyKey
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw SignalError.invalidResponse
        }
    }

    /// Performs a request and retries once if the server requires a renewed app session.
    /// Session creation bypasses bearer authentication; retries retain the same body and idempotency key.
    private func perform(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        idempotencyKey: UUID? = nil,
        authenticating: Bool = false,
        canRenew: Bool = true
    ) async throws -> Data {
        guard hasValidAPIKey else {
            #if DEBUG
            Self.logger.debug("Signal requires a valid app API key from the dashboard Integration tab.")
            #endif

            throw SignalError.invalidConfiguration
        }

        let session = authenticating ? nil : try await verifiedSession()
        try Task.checkCancellation()

        var request = try makeRequest(
            path: path, method: method, query: query, body: body, idempotencyKey: idempotencyKey
        )

        if let session {
            request.setValue("Bearer " + session.token, forHTTPHeaderField: "Authorization")
        }

        let (data, status) = try await transmit(request)

        if (200..<300).contains(status) {
            return data
        }

        let errorCode = (try? JSONDecoder().decode(SignalErrorResponse.self, from: data))?.error

        if status == 403, errorCode == "verification_required" {
            if authenticating, body?["app_transaction"] == nil {
                throw SignalVerificationRequired()
            }

            if authenticating == false, canRenew {
                // Discard only the session this request used; a concurrent caller may already have renewed.
                if verified?.token == session?.token {
                    verified = nil
                }

                return try await perform(
                    path: path, method: method, query: query, body: body,
                    idempotencyKey: idempotencyKey, canRenew: false
                )
            }
        }

        throw failure(status: status, errorCode: errorCode, authenticating: authenticating)
    }

    /// Builds an HTTPS Signal request with the app API key and optional JSON body and idempotency key.
    private func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: [String: Any]?,
        idempotencyKey: UUID?
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.kickstart.tools"
        components.path = "/signal/v1/" + path
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else {
            throw SignalError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-Kickstart-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        if let idempotencyKey {
            request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        return request
    }

    /// Sends one request, keeping cancellation distinct from connection failures.
    private func transmit(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            #if DEBUG
            Self.logger.debug(
                "Signal could not connect to the feedback service. Check the network connection and try again."
            )
            #endif
            throw SignalError.connection
        }
    }

    /// Maps a failed response to a `SignalError`, logging developer guidance in debug builds.
    private func failure(status: Int, errorCode: String?, authenticating: Bool) -> SignalError {
        #if DEBUG
        Self.logger.debug("Signal request failed with HTTP status \(status).")
        #endif

        switch (status, errorCode) {
        case (403, "verification_required"):
            #if DEBUG
            Self.logger.debug("Signal verification_required: the application session could not be renewed.")
            #endif
            return .appVerification
        case (403, "app_verification_failed"):
            #if DEBUG
            Self.logger.debug("Signal app_verification_failed: use a valid App Store or TestFlight build.")
            #endif
            return .appVerification
        case (403, "feature_disabled"):
            #if DEBUG
            Self.logger.debug("Signal feature_disabled: this action is disabled in the board settings.")
            #endif
            return .unavailable
        case (403, _):
            #if DEBUG
            Self.logger.debug("Signal request unavailable for this app.")
            #endif
            return .unavailable
        case (400, _):
            return .invalidConfiguration
        case (404, _) where authenticating || errorCode == "invalid_api_key":
            #if DEBUG
            Self.logger.debug(
                "Signal invalid_api_key: use the current app API key from the dashboard Integration tab."
            )
            #endif
            return .invalidConfiguration
        case (404, _):
            return .notFound
        case (413, _), (422, _):
            return .invalidContent
        case (429, _):
            return .rateLimited
        case (500...599, _):
            return .server
        default:
            return .invalidResponse
        }
    }
}
