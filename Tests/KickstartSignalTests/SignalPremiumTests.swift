//
// SignalPremiumTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import SwiftUI
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Signal premium support")
struct SignalPremiumTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func modelForwardsPremiumStatusWithoutChangingVoteOrCommentBehavior(isPremium: Bool) async throws {
        let suite = "SignalPremiumTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("vote"),
                try SignalFixture.response("remove_vote"),
                try SignalFixture.response("create_comment")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { throw SignalError.appVerification },
            transport: { try await recorder.send($0) }
        )

        let model = SignalDetailModel(request: SignalFixture.request(), client: client)
        await model.toggleVote(isPremium: isPremium)
        #expect(model.hasVoted)

        await model.toggleVote(isPremium: isPremium)
        #expect(model.hasVoted == false)
        #expect(await model.submitComment("Thanks", limit: 500, isPremium: isPremium))
        #expect(model.error == nil)

        let requests = await recorder.recorded()

        for index in [1, 3] {
            let data = try #require(requests[index].httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["is_premium"] as? Bool == (isPremium ? true : nil))
            #expect(body["anonymous_id"] is String)
        }

        let undoData = try #require(requests[2].httpBody)
        let undo = try #require(JSONSerialization.jsonObject(with: undoData) as? [String: Any])
        #expect(Set(undo.keys) == ["anonymous_id"])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [
        #"{"error":"verification_required"}"#,
        #"{"error":"verification_required","retry_after":1,"details":{"expired":true}}"#
    ])
    func renewalRetainsPremiumFlagAndCommentIdempotencyKey(errorBody: String) async throws {
        let denied = (Data(errorBody.utf8), 403)
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                denied,
                try SignalFixture.response("session"),
                try SignalFixture.response("create_comment")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { throw SignalError.appVerification },
            transport: { try await recorder.send($0) }
        )

        let key = UUID()

        _ = try await client.createComment(
            requestID: SignalFixture.requestID,
            body: "Thanks",
            isPremium: true,
            idempotencyKey: key
        )

        let requests = await recorder.recorded()

        for index in [1, 3] {
            let data = try #require(requests[index].httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["is_premium"] as? Bool == true)
            #expect(requests[index].value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString)
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func environmentInheritsFromAncestorsAndAllowsOverrides() {
        #expect(EnvironmentValues().kickstartPremiumUser == false)
        let probe = PremiumEnvironmentRecorder()
        let renderer = ImageRenderer(content:
            VStack {
                PremiumEnvironmentReader(probe: probe, name: "inherited")
                PremiumEnvironmentReader(probe: probe, name: "override")
                    .kickstartPremiumUser(false)
            }
            .kickstartPremiumUser(true)
        )

        #expect(renderer.cgImage != nil)
        #expect(probe.values["inherited"] == true)
        #expect(probe.values["override"] == false)

        renderer.content = VStack {
            PremiumEnvironmentReader(probe: probe, name: "inherited")
            PremiumEnvironmentReader(probe: probe, name: "override")
                .kickstartPremiumUser(false)
        }.kickstartPremiumUser(false)

        #expect(renderer.cgImage != nil)
        #expect(probe.values["inherited"] == false)
    }
}
