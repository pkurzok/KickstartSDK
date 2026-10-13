//
// SignalNetworkingTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal networking privacy")
struct SignalNetworkingTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func signalSessionDisablesCookiesAndCachingAndBoundsTimeouts() throws {
        let session = SignalClient.makeSession()
        defer { session.invalidateAndCancel() }

        let config = session.configuration
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(config.timeoutIntervalForRequest == 30)
        #expect(config.timeoutIntervalForResource == 60)
        #expect(session.delegate is SignalRedirectDelegate)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func redirectDelegateNeverForwardsCredentials() async throws {
        let session = SignalClient.makeSession()
        defer { session.invalidateAndCancel() }

        let source = try #require(URL(string: "https://api.kickstart.tools/signal/v1/config"))
        let target = try #require(URL(string: "https://other.example.test/collect"))
        let response = try #require(HTTPURLResponse(
            url: source, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString]
        ))

        var redirected = URLRequest(url: target)
        redirected.setValue(SignalFixture.apiKey, forHTTPHeaderField: "X-Kickstart-API-Key")
        redirected.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let delegate = try #require(session.delegate as? SignalRedirectDelegate)
        let task = session.dataTask(with: source)
        defer { task.cancel() }
        let accepted = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) {
                continuation.resume(returning: $0)
            }
        }
        #expect(accepted == nil)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["", "preview", "ks_live_" + String(repeating: "a", count: 42),
        "ks_live_" + String(repeating: "a", count: 42) + "!"])
    func malformedKeysDoNotStartVerificationOrNetworking(key: String) async throws {
        let recorder = SignalTransportRecorder(responses: [])

        let client = SignalClient(
            apiKey: key,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { throw SignalError.appVerification },
            transport: { try await recorder.send($0) }
        )

        await #expect(throws: SignalError.invalidConfiguration) { try await client.loadConfiguration() }
        #expect(await recorder.recorded().isEmpty)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func connectionFailuresUseASafeError() async throws {
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { _ in
                throw URLError(
                    .notConnectedToInternet,
                    userInfo: [NSLocalizedDescriptionKey: "Private transport details"]
                )
            }
        )

        await #expect(throws: SignalError.connection) {
            try await client.loadConfiguration()
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func transportCancellationDoesNotBecomeAConnectionFailure(urlCancellation: Bool) async throws {
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { _ in
                if urlCancellation {
                    throw URLError(.cancelled)
                }

                throw CancellationError()
            }
        )

        await #expect(throws: CancellationError.self) { try await client.loadConfiguration() }
    }
}
