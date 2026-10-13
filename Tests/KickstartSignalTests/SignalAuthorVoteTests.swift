//
// SignalAuthorVoteTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal author votes")
struct SignalAuthorVoteTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func submissionRemembersAuthorVoteAndForwardsPremiumStatus(isPremium: Bool) async throws {
        let suite = "SignalAuthorVoteTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("create_request")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let model = SignalSubmissionModel(client: client, limits: .standard)
        model.title = "Folders"
        await model.submit(isPremium: isPremium)

        #expect(model.submitted)
        #expect(client.hasVoted(requestID: SignalFixture.requestID))
        #expect(SignalIdentityStore(defaults: defaults).votedIDs().contains(SignalFixture.requestID))
        let published = SignalDetailModel(request: SignalFixture.request(votes: 1), client: client)
        #expect(published.hasVoted)
        let calls = await recorder.recorded()
        #expect(calls.map { $0.url?.path } == ["/signal/v1/sessions", "/signal/v1/requests"])
        let data = try #require(calls.last?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["is_premium"] as? Bool == (isPremium ? true : nil))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func lostResponseRetryRecoversAuthorVoteWithoutAnotherVoteRequest() async throws {
        let recorder = SignalTransportRecorder(responses: [try SignalFixture.response("session")])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let model = SignalSubmissionModel(client: client, limits: .standard)
        model.title = "Folders"
        model.description = "Organize things"
        await model.submit()
        #expect(model.submitted == false)
        #expect(model.error != nil)
        #expect(client.hasVoted(requestID: SignalFixture.requestID) == false)

        let (body, _) = try SignalFixture.response("create_request")
        await recorder.enqueue((body, 200))
        await model.submit()
        #expect(model.submitted)
        #expect(model.error == nil)
        #expect(client.hasVoted(requestID: SignalFixture.requestID))
        let calls = await recorder.recorded()
        try #require(calls.count == 3)
        let firstKey = try #require(calls[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(firstKey == calls[2].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(try SignalFixture.body(calls[1]) == SignalFixture.body(calls[2]))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func creationRetryKeepsAnUndoneAuthorVoteRemoved() async throws {
        let receipt = SignalSubmission(id: SignalFixture.requestID, hasVoted: false)
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("create_request"),
            try SignalFixture.encoded(SignalFixture.request(votes: 0)),
            try SignalFixture.encoded(receipt)
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let key = UUID()
        let created = try await client.createRequest(title: "Folders", description: "", idempotencyKey: key)
        #expect(client.hasVoted(requestID: created.id))
        let published = SignalDetailModel(request: SignalFixture.request(votes: 1), client: client)
        await published.toggleVote()
        #expect(published.hasVoted == false)
        #expect(published.request.voteCount == 0)
        _ = try await client.createRequest(title: "Folders", description: "", idempotencyKey: key)
        #expect(client.hasVoted(requestID: created.id) == false)
        let calls = await recorder.recorded()
        #expect(calls[2].httpMethod == "DELETE")
        #expect(calls.count == 4)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func olderServersLeaveSavedVotesUnchanged(hasVoted: Bool) async throws {
        let identities = SignalIdentityStore(defaults: nil)
        identities.setVote(hasVoted, requestID: SignalFixture.requestID)
        let legacy = Data("{\"id\":\"\(SignalFixture.requestID)\",\"moderation_state\":\"unpublished\"}".utf8)
        let recorder = SignalTransportRecorder(responses: [try SignalFixture.response("session"), (legacy, 201)])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let receipt = try await client.createRequest(title: "Folders", description: "")
        #expect(receipt.hasVoted == nil)
        #expect(client.hasVoted(requestID: receipt.id) == hasVoted)
    }
}
