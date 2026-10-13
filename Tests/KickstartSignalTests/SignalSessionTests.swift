//
// SignalSessionTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@Suite("Signal session verification")
struct SignalSessionTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func verifiedSessionAndConfigurationUseOnlySignalEndpoints() async throws {
        let challenge = (Data(#"{"error":"verification_required"}"#.utf8), 403)
        let recorder = SignalTransportRecorder(
            responses: [challenge, try SignalFixture.response("session"), try SignalFixture.response("config")]
        )
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture" },
            bundleID: "com.example.signal",
            transport: { try await recorder.send($0) }
        )

        let config = try await client.loadConfiguration()
        #expect(config.interactionsEnabled)
        #expect(config.limits.title == 80)
        #expect(config.limits.description == 500)
        #expect(config.limits.comment == 500)

        let requests = await recorder.recorded()
        #expect(requests.map { $0.url?.path } == ["/signal/v1/sessions", "/signal/v1/sessions", "/signal/v1/config"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Kickstart-API-Key") == SignalFixture.apiKey })
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[2].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer kss_") == true)

        let probe = try JSONDecoder().decode([String: String].self, from: #require(requests[0].httpBody))
        #expect(probe == ["bundle_id": "com.example.signal", "sdk_version": kickstartSDKVersion])

        let payload = try JSONDecoder().decode([String: String].self, from: #require(requests[1].httpBody))
        #expect(payload == [
            "bundle_id": "com.example.signal", "sdk_version": kickstartSDKVersion, "app_transaction": "signed-fixture"
        ])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func missingBinaryEvidenceStopsAfterTheServerRequiresVerification() async throws {
        let challenge = (Data(#"{"error":"verification_required"}"#.utf8), 403)
        let recorder = SignalTransportRecorder(responses: [challenge])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { throw SignalError.appVerification },
            transport: { try await recorder.send($0) }
        )

        await #expect(throws: SignalError.appVerification) { try await client.loadConfiguration() }
        #expect(await recorder.recorded().map { $0.url?.path } == ["/signal/v1/sessions"])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func xcodeTestingDoesNotRequestAnyStoreKitEvidence() async throws {
        let recorder = SignalTransportRecorder(
            responses: [try SignalFixture.response("session"), try SignalFixture.response("config")]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: {
                Issue.record("StoreKit must not be called when the server allows Xcode testing.")
                throw SignalError.appVerification
            },
            bundleID: "com.example.signal",
            transport: { try await recorder.send($0) }
        )

        #expect(try await client.loadConfiguration().interactionsEnabled)
        let requests = await recorder.recorded()
        #expect(requests.count == 2)
        #expect(try SignalFixture.body(requests[0]) == [
            "bundle_id": "com.example.signal", "sdk_version": kickstartSDKVersion
        ])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func repeatedVerificationChallengeDoesNotLoopOrDowngrade() async throws {
        let challenge = (Data(#"{"error":"verification_required"}"#.utf8), 403)
        let recorder = SignalTransportRecorder(responses: [challenge, challenge])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        await #expect(throws: SignalError.appVerification) { try await client.loadConfiguration() }
        #expect(await recorder.recorded().count == 2)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test(arguments: [true, false])
    func expiredSessionRenewsOnce(requiresEvidence: Bool) async throws {
        let denied = (Data(#"{"status":"error","error":"verification_required"}"#.utf8), 403)

        var responses: [(Data, Int)] = []

        if requiresEvidence { responses.append(denied) }
        responses += [try SignalFixture.response("session"), denied]

        if requiresEvidence { responses.append(denied) }
        responses += [try SignalFixture.response("session"), try SignalFixture.response("config")]

        let recorder = SignalTransportRecorder(responses: responses)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: {
                #expect(requiresEvidence, "Xcode testing must renew without StoreKit.")
                return "signed-fixture"
            },
            transport: { try await recorder.send($0) }
        )

        #expect(try await client.loadConfiguration().interactionsEnabled)

        let requests = await recorder.recorded()
        #expect(requests.count == (requiresEvidence ? 6 : 4))
        #expect(requests.count { $0.url?.path == "/signal/v1/config" } == 2)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test(arguments: [901, 3_600, 86_400])
    func serverExpiryCanExceedFifteenMinutes(expiresIn: Int) async throws {
        let token = "kss_" + String(repeating: "b", count: 43)
        let session = Data("{\"session_token\":\"\(token)\",\"expires_in\":\(expiresIn)}".utf8)
        let recorder = SignalTransportRecorder(
            responses: [(session, 201), try SignalFixture.response("config"), try SignalFixture.response("config")]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.loadConfiguration()
        _ = try await client.loadConfiguration()

        let calls = await recorder.recorded()
        #expect(calls.map { $0.url?.path } == ["/signal/v1/sessions", "/signal/v1/config", "/signal/v1/config"])
        #expect(calls.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + token })
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test(arguments: [1, 43, 80])
    func sessionTokensDoNotRequireAFixedLength(length: Int) async throws {
        let token = "kss_" + String(repeating: "b", count: length)
        let session = try JSONSerialization.data(withJSONObject: ["session_token": token, "expires_in": 900])
        let recorder = SignalTransportRecorder(responses: [(session, 200), try SignalFixture.response("config")])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.loadConfiguration()
        let calls = await recorder.recorded()
        #expect(calls.last?.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test(arguments: [0, -1, Int.min])
    func nonpositiveSessionExpiryIsRejected(expiresIn: Int) async throws {
        let token = "kss_" + String(repeating: "b", count: 43)
        let session = Data("{\"session_token\":\"\(token)\",\"expires_in\":\(expiresIn)}".utf8)
        let recorder = SignalTransportRecorder(responses: [(session, 201)])

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture" },
            transport: { try await recorder.send($0) }
        )

        await #expect(throws: SignalError.invalidResponse) { try await client.loadConfiguration() }
        #expect(await recorder.recorded().map { $0.url?.path } == ["/signal/v1/sessions"])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor @Test
    func shortPositiveExpiryIsAcceptedAndRenewedBeforeReuse() async throws {
        let token = "kss_" + String(repeating: "b", count: 43)
        let session = Data("{\"session_token\":\"\(token)\",\"expires_in\":1}".utf8)

        let recorder = SignalTransportRecorder(
            responses: [
                (session, 201),
                try SignalFixture.response("config"),
                try SignalFixture.response("session"),
                try SignalFixture.response("config")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "signed-fixture"},
            transport: { try await recorder.send($0) }
        )

        _ = try await client.loadConfiguration()
        _ = try await client.loadConfiguration()

        let calls = await recorder.recorded()
        #expect(calls.map { $0.url?.path } == [
            "/signal/v1/sessions", "/signal/v1/config", "/signal/v1/sessions", "/signal/v1/config"
        ])
        #expect(calls[1].value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
        #expect(calls[3].value(forHTTPHeaderField: "Authorization") != "Bearer " + token)
    }
}
