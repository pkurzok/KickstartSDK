//
// SignalClientTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@Suite("Signal isolated transport")
struct SignalClientTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false])
    @MainActor
    func forbiddenResponsesUseTheirErrorCode(authenticating: Bool) async throws {
        let variants = [
            ("signal_unavailable", SignalError.unavailable),
            ("feature_disabled", .unavailable),
            ("app_verification_failed", .appVerification),
            ("unknown_future_error", .unavailable),
            ("", .unavailable)
        ]

        for (code, expected) in variants {
            let failure = (Data("{\"error\":\"\(code)\",\"message\":\"Private server details\"}".utf8), 403)
            let responses = authenticating ? [failure] : [try SignalFixture.response("session"), failure]
            let recorder = SignalTransportRecorder(responses: responses)

            let client = SignalClient(
                apiKey: SignalFixture.apiKey,
                identities: SignalIdentityStore(defaults: nil),
                appTransaction: { "fixture" },
                transport: { try await recorder.send($0) }
            )

            await #expect(throws: expected) { try await client.loadConfiguration() }
            #expect(await recorder.recorded().count == (authenticating ? 1 : 2))
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [true, false], ["not_found", "invalid_api_key"])
    @MainActor
    func notFoundDistinguishesMissingRequestsFromUnknownKeys(authenticating: Bool, code: String) async throws {
        let failure = (Data("{\"error\":\"\(code)\"}".utf8), 404)
        let responses = authenticating ? [failure] : [try SignalFixture.response("session"), failure]
        let recorder = SignalTransportRecorder(responses: responses)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let expected: SignalError = authenticating || code == "invalid_api_key" ? .invalidConfiguration : .notFound
        await #expect(throws: expected) {
            try await client.loadConfiguration()
        }

        #expect(await recorder.recorded().count == (authenticating ? 1 : 2))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func identityAndVotesPersistWithinAnAppAndStaySeparateFromOtherApps() throws {
        let suite = "SignalTests." + UUID().uuidString
        let otherSuite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let otherDefaults = try #require(UserDefaults(suiteName: otherSuite))

        defer {
            defaults.removePersistentDomain(forName: suite)
            otherDefaults.removePersistentDomain(forName: otherSuite)
        }

        let first = SignalIdentityStore(defaults: defaults)
        let secondDefaults = try #require(UserDefaults(suiteName: suite))
        let second = SignalIdentityStore(defaults: secondDefaults)

        let otherApp = SignalIdentityStore(defaults: otherDefaults)
        #expect(first.identity() == second.identity())
        #expect(first.identity() != otherApp.identity())

        first.setVote(true, requestID: "ksreq_example")
        #expect(second.votedIDs() == ["ksreq_example"])
        #expect(otherApp.votedIDs().isEmpty)

        second.setVote(false, requestID: "ksreq_example")
        #expect(first.votedIDs().isEmpty)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func browsingCreatesNoPersistentIdentity() async throws {
        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("config"),
            try SignalFixture.response("list_requests"),
            try SignalFixture.response("list_comments")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.loadConfiguration()
        _ = try await client.listRequests()
        _ = try await client.listComments(requestID: SignalFixture.requestID)

        #expect((defaults.persistentDomain(forName: suite) ?? [:]).isEmpty)
        let calls = await recorder.recorded()
        #expect(calls.count == 4)
        #expect(calls.dropFirst().allSatisfy { $0.httpBody == nil })
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func savedVotesCanBeReadBeforeConfigurationWithoutVerificationOrNetworking() async throws {
        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let identities = SignalIdentityStore(defaults: defaults)
        identities.setVote(true, requestID: SignalFixture.requestID)

        let recorder = SignalTransportRecorder(responses: [])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { throw SignalError.appVerification },
            transport: { try await recorder.send($0) })

        #expect(client.hasVoted(requestID: SignalFixture.requestID))
        #expect(client.hasVoted(requestID: "another-request") == false)
        #expect(await recorder.recorded().isEmpty)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func creationRetryPreservesIdempotencyAndExcludesProfiles() async throws {
        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("create_request"),
                try SignalFixture.response("create_request")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        let key = UUID()
        _ = try await client.createRequest(title: "Folders", description: "Organize things", idempotencyKey: key)
        _ = try await client.createRequest(title: "Folders", description: "Organize things", idempotencyKey: key)

        let requests = await recorder.recorded()
        #expect(requests.map { $0.url?.path } == ["/signal/v1/sessions", "/signal/v1/requests", "/signal/v1/requests"])
        #expect(try SignalFixture.body(requests[1]) == SignalFixture.body(requests[2]))
        #expect(requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString })

        let body = try JSONDecoder().decode([String: String].self, from: #require(requests[1].httpBody))
        #expect(Set(body.keys) == ["anonymous_id", "title", "description"])
        #expect(UUID(uuidString: try #require(body["anonymous_id"])) != nil)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func commentCreationUsesTheAppIdentityWithoutFetchingConfiguration() async throws {
        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let identities = SignalIdentityStore(defaults: defaults)
        let identity = identities.identity()

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("create_comment")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.createComment(requestID: SignalFixture.requestID, body: "Thanks")

        let requests = await recorder.recorded()
        #expect(requests.map { $0.url?.path } == [
            "/signal/v1/sessions", "/signal/v1/requests/" + SignalFixture.requestID + "/comments"
        ])
        #expect(try SignalFixture.body(requests[1]) == ["anonymous_id": identity, "body": "Thanks"])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func rateLimitResponsesUseASafeError() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                (Data("private server details".utf8), 429)
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        await #expect(throws: SignalError.rateLimited) {
            try await client.listRequests()
        }
    }

    @Test
    func responseExamplesDecode() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(SignalRequestPage.self, from: SignalFixture.response("list_requests").0)
        let requests = page.requests

        #expect(requests.count == 1)
        #expect(requests.first?.creationOrder == 1)

        for operation in ["vote", "remove_vote"] {
            let request = try decoder.decode(SignalRequest.self, from: SignalFixture.response(operation).0)
            #expect(request.creationOrder == 1)
        }

        let comments = try decoder.decode(SignalCommentPage.self, from: SignalFixture.response("list_comments").0)
        #expect(comments.comments.count == 1)

        let submission = try decoder.decode(SignalSubmission.self, from: SignalFixture.response("create_comment").0)
        #expect(submission.id == "kscom_" + String(repeating: "b", count: 32))
        #expect(submission.hasVoted == nil)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func requestPagesDefaultToOneHundredAndPreserveOpaqueCursors() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("list_requests"),
                try SignalFixture.response("list_requests"),
                try SignalFixture.response("list_requests")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        let cursor = "kscursor_example"

        _ = try await client.listRequests()
        _ = try await client.listRequests(cursor: cursor)
        _ = try await client.listRequests(limit: 10)

        let calls = await recorder.recorded()

        let queries = try calls.dropFirst().map { call in
            let url = try #require(call.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }

        #expect(queries.map { $0["limit"] } == ["100", "100", "10"])
        #expect(queries.allSatisfy { $0["sort"] == "votes" })
        #expect(queries.allSatisfy { $0["status"] == nil })
        #expect(queries[1]["cursor"] == cursor)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: SignalStatus.allCases)
    @MainActor
    func requestPagesPreserveEachExactStatus(status: SignalStatus) async throws {
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("list_requests")
        ])

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.listRequests(status: status)

        let calls = await recorder.recorded()
        #expect(calls.count == 2)
        let request = try #require(calls.last)
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "status" }?.value == status.rawValue)
        #expect(query.first { $0.name == "sort" }?.value == "votes")
    }
}
