//
// SignalConcurrencyTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal concurrency and retry boundaries")
struct SignalConcurrencyTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func concurrentReadsShareOneVerifiedSession() async throws {
        let recorder = SignalSuspendedTransport(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("config"),
            try SignalFixture.response("config")
        ], blockedIndex: 0)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let first = Task { try await client.loadConfiguration() }
        await recorder.waitUntilBlocked()

        // This queued main-actor task can release verification only after the next call suspends.
        // Calling directly from this actor ensures both readers overlap the pending session request.
        let release = Task { @MainActor in await recorder.release() }
        let second = try await client.loadConfiguration()
        let firstConfiguration = try await first.value
        await release.value

        #expect(firstConfiguration.interactionsEnabled)
        #expect(second.interactionsEnabled)
        let requests = await recorder.recorded()
        #expect(requests.map { $0.url?.path } == [
            "/signal/v1/sessions", "/signal/v1/config", "/signal/v1/config"
        ])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func persistentVerificationFailureRenewsOnlyOnce() async throws {
        let denied = (Data(#"{"error":"verification_required"}"#.utf8), 403)
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                denied,
                try SignalFixture.response("session"),
                denied
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        await #expect(throws: SignalError.appVerification) { try await client.loadConfiguration() }
        #expect(await recorder.recorded().count == 4)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func creationRenewalKeepsTheOriginalIdentityPayloadAndIdempotencyKey() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                (Data(#"{"error":"verification_required"}"#.utf8), 403),
                try SignalFixture.response("session"),
                try SignalFixture.response("create_request")
            ]
        )

        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let key = UUID()
        _ = try await client.createRequest(title: "Folders", description: "Details", idempotencyKey: key)

        let requests = await recorder.recorded()
        #expect(requests.count == 4)
        #expect(try SignalFixture.body(requests[1]) == SignalFixture.body(requests[3]))
        #expect(requests[1].value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
        #expect(requests[3].value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func rotatingTheAPIKeyPreservesTheInstallationIdentityAndSavedVotes() async throws {
        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var sentIdentities: [String] = []

        for keyCharacter in ["a", "b"] {
            let key = "ks_live_" + String(repeating: keyCharacter, count: 43)

            let recorder = SignalTransportRecorder(
                responses: [
                    try SignalFixture.response("session"),
                    try SignalFixture.response("create_request")
                ]
            )

            let identities = SignalIdentityStore(defaults: defaults)
            let client = SignalClient(
                apiKey: key,
                identities: identities,
                appTransaction: { "fixture" },
                transport: { try await recorder.send($0) }
            )

            #expect(client.hasVoted(requestID: SignalFixture.requestID) == (sentIdentities.isEmpty == false))

            _ = try await client.createRequest(title: "Folders", description: "Details")

            let requests = await recorder.recorded()

            #expect(requests.map { $0.url?.path } == ["/signal/v1/sessions", "/signal/v1/requests"])
            #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Kickstart-API-Key") == key })

            sentIdentities.append(try #require(SignalFixture.body(requests[1])["anonymous_id"]))
            identities.setVote(true, requestID: SignalFixture.requestID)
        }

        #expect(sentIdentities[0] == sentIdentities[1])
    }
}
