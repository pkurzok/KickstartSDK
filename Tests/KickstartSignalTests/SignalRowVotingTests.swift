//
// SignalRowVotingTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Signal row voting")
struct SignalRowVotingTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func rowAndDetailsShareVoteStateAndKeepTheBoardOrdered() async {
        let older = SignalFixture.request(status: .open)

        let newer = SignalFixture.request(
            status: .open, id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 2
        )

        let board = SignalBoardModel(client: .demo(requests: [older, newer]), status: .open)
        await board.load()

        let row = board.detailModel(for: older)
        await row.toggleVote()
        #expect(row.error == nil)
        #expect(row.hasVoted)
        #expect(row.request.voteCount == 4)
        #expect(board.requests.map(\.id) == [older.id, newer.id])

        let details = board.detailModel(for: older)
        #expect(details === row)
        #expect(details.hasVoted)

        await details.toggleVote()
        #expect(row.hasVoted == false)
        #expect(row.request.voteCount == 3)
        #expect(board.requests.map(\.id) == [newer.id, older.id])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func failedRowVoteDoesNotBecomeAnInlineDetailError(hasVoted: Bool) async throws {
        let request = SignalFixture.request()
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            (Data(), 503),
            try SignalFixture.response("list_comments")
        ])
        let identities = SignalIdentityStore(defaults: nil)
        identities.setVote(hasVoted, requestID: request.id)
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let board = SignalBoardModel(client: client)
        board.allRequests = [request]
        let row = board.detailModel(for: request)

        let failure = await row.toggleVote()
        #expect(failure == SignalError.server.localizedDescription)
        #expect(row.error == nil)
        #expect(row.hasVoted == hasVoted)
        #expect(row.request == request)
        #expect(board.requests == [request])
        #expect(row.isBusy == false)

        let detail = board.detailModel(for: request)
        #expect(detail === row)
        await detail.load()
        #expect(detail.error == nil)
        #expect(detail.comments.count == 1)
        #expect(detail.hasVoted == hasVoted)
        #expect(await recorder.recorded().count == 3)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func pendingVoteBlocksRepeatedTapsAndRetainsThePremiumFlag() async throws {
        let request = SignalFixture.request(status: .open)
        let recorder = SignalSuspendedTransport(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.encoded(SignalFixture.request(votes: 4, status: .open))
            ],
            blockedIndex: 1
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: .open)
        board.allRequests = [request]

        let row = board.detailModel(for: request)
        let voting = Task { await row.toggleVote(isPremium: true) }

        await recorder.waitUntilBlocked()
        #expect(row.isBusy)

        let details = board.detailModel(for: request)
        #expect(details === row)

        #expect(await details.toggleVote() == nil)
        await recorder.release()
        #expect(await voting.value == nil)
        #expect(row.isBusy == false)
        #expect(row.hasVoted)

        let calls = await recorder.recorded()
        #expect(calls.count == 2)

        let body = try #require(calls.last?.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(payload["is_premium"] as? Bool == true)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func returningToTheBoardKeepsTheExistingRowModelAndSavedVoteWithoutReloading() async throws {
        let original = SignalFixture.request(status: .open)
        let refreshed = SignalFixture.request(votes: 24, status: .open)

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                try SignalFixture.encoded(refreshed)
            ],
            statusPages: try SignalFixture.statusPages([original])
        )

        let identities = SignalIdentityStore(defaults: nil)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: .open)
        await board.load()

        let row = board.detailModel(for: original)
        await row.toggleVote()

        let callsBeforeReturning = await recorder.recorded().count
        board.status = .planned
        #expect(board.requests.isEmpty)

        board.status = .open
        await board.load()
        #expect(board.detailModel(for: refreshed) === row)
        #expect(row.request == refreshed)
        #expect(row.hasVoted)
        #expect(board.requests == [refreshed])
        #expect(await recorder.recorded().count == callsBeforeReturning)
    }
}
