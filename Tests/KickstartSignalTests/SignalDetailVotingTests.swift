//
// SignalDetailVotingTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal detail voting")
struct SignalDetailVotingTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func detailVoteAndUndoUpdateTheBoardAndReorderLoadedRows() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.encoded(SignalFixture.request(votes: 4)),
                try SignalFixture.encoded(SignalFixture.request(votes: 3))
            ]
        )
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) })

        let board = SignalBoardModel(client: client)
        let other = SignalFixture.request(votes: 3, id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 2)
        board.allRequests = [other, SignalFixture.request()]

        let detail = board.detailModel(for: SignalFixture.request())
        await detail.toggleVote()
        #expect(detail.hasVoted)
        #expect(detail.error == nil)
        #expect(board.requests.first?.id == detail.request.id)
        #expect(board.requests.first?.voteCount == 4)

        await detail.toggleVote()
        #expect(detail.hasVoted == false)
        #expect(board.requests.map(\.id) == [other.id, detail.request.id])
        #expect(board.requests.first { $0.id == detail.request.id }?.voteCount == 3)
        #expect(client.hasVoted(requestID: detail.request.id) == false)

        let calls = await recorder.recorded()
        #expect(calls.map { $0.httpMethod } == ["POST", "POST", "DELETE"])
        let votesPath = "/signal/v1/requests/" + detail.request.id + "/votes"
        #expect(calls.map { $0.url?.path } == ["/signal/v1/sessions", votesPath, votesPath])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func voteUsesAuthoritativeCountWithoutRefreshAndFailedUndoKeepsItsState() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.encoded(SignalFixture.request(votes: 17)),
                (Data(), 503)
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client)
        board.allRequests = [SignalFixture.request()]
        let detail = board.detailModel(for: SignalFixture.request())

        await detail.toggleVote()
        #expect(detail.error == nil)
        #expect(detail.hasVoted)
        #expect(board.requests.first?.voteCount == 17)

        let failure = await detail.toggleVote()
        #expect(failure == SignalError.server.localizedDescription)
        #expect(detail.hasVoted)
        #expect(detail.request.voteCount == 17)
        #expect(board.requests.first?.voteCount == 17)
        #expect(client.hasVoted(requestID: detail.request.id))
        #expect(detail.error == nil)
        #expect(await recorder.recorded().count == 3)
        #expect(detail.isBusy == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func cancelledVoteKeepsItsStateWithoutAnAlert(hasVoted: Bool) async {
        let request = SignalFixture.request()
        let identities = SignalIdentityStore(defaults: nil)
        identities.setVote(hasVoted, requestID: request.id)
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { request in
                if request.url?.path == "/signal/v1/sessions" {
                    return try SignalFixture.response("session")
                }

                throw CancellationError()
            }
        )
        let detail = SignalDetailModel(request: request, client: client)

        #expect(await detail.toggleVote() == nil)
        #expect(detail.error == nil)
        #expect(detail.hasVoted == hasVoted)
        #expect(detail.request == request)
        #expect(client.hasVoted(requestID: request.id) == hasVoted)
        #expect(detail.isBusy == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func votingUsesCurrentServerPermissionAfterAnEarlierDisabledConfiguration() async throws {
        let disabled = SignalConfiguration(
            interactionsEnabled: false,
            limits: SignalContentLimits.standard
        )

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.encoded(disabled),
                try SignalFixture.response("vote")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        #expect(try await client.loadConfiguration().interactionsEnabled == false)

        let updated = try await client.vote(requestID: SignalFixture.requestID)
        #expect(updated.voteCount == 4)
        #expect(client.hasVoted(requestID: updated.id))
        #expect(await recorder.recorded().count == 3)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func creationOrderKeepsTiesConsistentAcrossPaginationAndNavigation() async throws {
        let older = SignalFixture.request(creationOrder: 2)
        let newer = SignalFixture.request(id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 3)
        let last = SignalFixture.request(id: "ksreq_" + String(repeating: "c", count: 32))

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                try SignalFixture.encoded(SignalFixture.request(votes: 4, creationOrder: 2)),
                try SignalFixture.encoded(SignalRequestPage(requests: [older, last], nextCursor: nil)),
                try SignalFixture.encoded(older),
                try SignalFixture.encoded(SignalFixture.request(votes: 4, id: last.id)),
                try SignalFixture.encoded(last)
            ],

            statusPages: try SignalFixture.statusPages([newer, older], cursors: [.planned: "page-two"])
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: .planned)
        await board.load()

        let detail = board.detailModel(for: older)
        await detail.toggleVote()
        #expect(board.requests.map(\.id) == [older.id, newer.id])

        await board.loadMore(in: .planned)
        #expect(board.requests.map(\.id) == [older.id, newer.id, last.id])

        await detail.toggleVote()
        #expect(board.error == nil)
        #expect(detail.error == nil)
        #expect(board.requests.map(\.id) == [newer.id, older.id, last.id])

        await board.load()
        let refreshedDetail = board.detailModel(for: last)
        await refreshedDetail.toggleVote()
        await refreshedDetail.toggleVote()
        #expect(refreshedDetail.error == nil)
        #expect(board.requests.map(\.id) == [newer.id, older.id, last.id])
        #expect(await recorder.recorded().count == 12)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [UInt64(1), UInt64(UInt32.max) + 1])
    func newlyTiedRequestsUseCreationOrderInsteadOfTheirInitialRanking(firstOrder: UInt64) async throws {
        let older = SignalFixture.request(votes: 3, status: .open, creationOrder: firstOrder)
        // Deliberately reverse the public ID order: opaque IDs do not encode age.
        let newerID = "ksreq_" + String(repeating: "0", count: 32)
        let newer = SignalFixture.request(votes: 2, status: .planned, id: newerID, creationOrder: firstOrder + 1)
        let tied = SignalFixture.request(votes: 3, status: .open, id: newerID, creationOrder: firstOrder + 1)

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"), try SignalFixture.response("config"),
                try SignalFixture.encoded(tied), try SignalFixture.encoded(newer)
            ],
            statusPages: try SignalFixture.statusPages([older, newer])
        )
        let client = SignalClient(apiKey: SignalFixture.apiKey, identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" }, transport: { try await recorder.send($0) })
        let board = SignalBoardModel(client: client)
        await board.load()
        #expect(board.requests.map(\.id) == [older.id, newer.id])

        let detail = board.detailModel(for: newer)
        await detail.toggleVote()
        #expect(detail.error == nil)
        #expect(board.requests.map(\.id) == [newer.id, older.id])
        #expect(board.requests.first?.creationOrder == firstOrder + 1)

        await detail.toggleVote()
        #expect(detail.error == nil)
        #expect(board.requests.map(\.id) == [older.id, newer.id])
        #expect(await recorder.recorded().count == 9)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func paginationSortsImmediatelyAfterUndoMovesALoadedRequest() async throws {
        let initial = SignalFixture.request(votes: 3, status: .open, creationOrder: 3)
        let undone = SignalFixture.request(votes: 2, status: .inProgress, creationOrder: 3)

        let next = SignalFixture.request(votes: 3, status: .open,
            id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 2)
        let last = SignalFixture.request(votes: 1, status: .open,
            id: "ksreq_" + String(repeating: "c", count: 32), creationOrder: 1)

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                try SignalFixture.encoded(undone),
                try SignalFixture.encoded(SignalRequestPage(requests: [next, last], nextCursor: nil))
            ],
            statusPages: try SignalFixture.statusPages([initial], cursors: [.open: "next-page"])
        )

        let identities = SignalIdentityStore(defaults: nil)
        identities.setVote(true, requestID: initial.id)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) })

        let board = SignalBoardModel(client: client)
        await board.load()
        #expect(board.requests == [initial])

        let detail = board.detailModel(for: initial)
        await detail.load(interactionsEnabled: false)
        #expect(detail.hasVoted)

        await detail.toggleVote()
        #expect(detail.hasVoted == false)
        #expect(detail.error == nil)
        #expect(board.requests == [undone])
        #expect(board.sectionCursors[.open] == "next-page")

        await board.loadMore(in: .open)
        // Assert immediately: another vote would sort again and conceal the bug.
        #expect(board.requests == [next, undone, last])
        #expect(board.nextCursor == nil)
        #expect(board.error == nil)
        #expect(board.isLoading == false)

        let calls = await recorder.recorded()
        #expect(calls.count == 9)
        #expect(calls[7].httpMethod == "DELETE")

        let pageURL = try #require(calls.last?.url)
        let query = try #require(URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "sort", value: "votes")))
        #expect(query.contains(URLQueryItem(name: "cursor", value: "next-page")))
    }
}
