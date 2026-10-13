//
// SignalBoardPagingTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Signal board page sizes")
struct SignalBoardPagingTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func paginationSurvivesAStatusChangeAndPreservesACompletedVote() async throws {
        let open = SignalFixture.request(status: .open)
        let planned = SignalFixture.request(status: .planned, id: "ksreq_" + String(repeating: "b", count: 32))
        let next = SignalFixture.request(
            status: .open, id: "ksreq_" + String(repeating: "c", count: 32), creationOrder: 2
        )
        let voted = SignalFixture.request(votes: 17, status: .open)

        let statusPages = try SignalFixture.statusPages([open, planned], cursors: [.open: "open-page-2"])
        let recorder = SignalSuspendedTransport(responses: [
            try SignalFixture.response("session"), try SignalFixture.response("config"),
            try SignalFixture.encoded(SignalRequestPage(requests: [open, next, next], nextCursor: nil)),
            try SignalFixture.encoded(voted)
        ], blockedIndex: 7, statusPages: statusPages)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture"  },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: .open)
        await board.load()

        let row = board.detailModel(for: open)
        let loading = Task { await board.loadMore(in: .open) }
        await recorder.waitUntilBlocked()

        board.status = .planned
        #expect(board.requests == [planned])

        await board.load()
        await row.toggleVote()
        #expect(row.error == nil)
        #expect(row.hasVoted)

        await recorder.release()
        await loading.value
        #expect(board.requests == [planned])

        board.status = .open
        #expect(board.requests == [voted, next])
        #expect(board.nextCursor == nil)
        #expect(board.detailModel(for: voted) === row)
        #expect(board.error == nil)
        #expect(board.isLoading == false)
        #expect(await recorder.recorded().count == 9)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 4, 100, 101])
    func allLoadsOneHundredPerStatusAndPagesEachSectionIndependently(count: Int) async {
        let samples = SignalStatus.allCases.enumerated().flatMap { statusIndex, status in
            (0..<count).map { index in
                SignalFixture.request(
                    votes: statusIndex * count + index, status: status,
                    id: "ksreq_" + UUID().uuidString.replacing("-", with: "").lowercased(),
                    creationOrder: UInt64(statusIndex * count + index + 1)
                )
            }
        }

        let board = SignalBoardModel(client: .demo(requests: samples))
        #expect(board.status == nil)

        await board.load()
        #expect(board.error == nil)
        #expect(board.nextCursor == nil)
        #expect(board.requests.count == min(count, 100) * SignalStatus.allCases.count)

        let statuses: [SignalStatus] = count == 0 ? [] : [.open, .inProgress, .planned, .completed, .declined]
        #expect(board.sections.map(\.status) == statuses)
        #expect(board.sections.allSatisfy { $0.requests.count == min(count, 100) })
        #expect(board.sectionCursors.count == (count > 100 ? SignalStatus.allCases.count : 0))

        if count > 100 {
            await board.loadMore(in: .open)
            #expect(board.error == nil)
            #expect(board.sections.first?.requests.count == count)
            #expect(board.sections.dropFirst().allSatisfy { $0.requests.count == 100 })
            #expect(board.sectionCursors[.open] == nil)
            #expect(board.sectionCursors.count == SignalStatus.allCases.count - 1)
            #expect(board.sections.map(\.status) == statuses)

            board.status = .planned
            #expect(board.requests.count == 100)
            #expect(board.requests.allSatisfy { $0.status == .planned })
            #expect(board.sectionCursors.count == SignalStatus.allCases.count - 1)
            #expect(board.nextCursor != nil)

            await board.loadMore(in: .planned)
            #expect(board.requests.count == count)
            #expect(board.nextCursor == nil)

            board.status = nil
            await board.load()

            #expect(board.error == nil)
            #expect(board.requests.count == 100 * SignalStatus.allCases.count + 2)
            #expect(board.sections.map(\.status) == statuses)
            #expect(board.sectionCursors.count == SignalStatus.allCases.count - 2)
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [3, 100, 101])
    func commentsLoadOneHundredBeforeOfferingAnotherPage(count: Int) async {
        let request = SignalFixture.request()

        let comments = (0..<count).map { index in
            SignalComment(
                id: "kscom_" + UUID().uuidString.replacing("-", with: "").lowercased(),
                body: "Comment \(index)", isDeveloper: index == 1,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let client = SignalClient.demo(requests: [request], comments: [request.id: comments])
        let detail = SignalDetailModel(request: request, client: client)
        await detail.load(interactionsEnabled: true)

        #expect(detail.commentsError == nil)
        #expect(detail.comments.map(\.id) == comments.prefix(100).map(\.id))
        #expect((detail.commentsCursor != nil) == (count > 100))
        #expect(detail.developerReplies.count == 1)

        if count > 100 {
            await detail.load(cursor: detail.commentsCursor)
            #expect(detail.commentsError == nil)
            #expect(detail.comments.map(\.id) == comments.map(\.id))
            #expect(detail.commentsCursor == nil)
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func allWaitsForEveryStatusAndSelectionDoesNotTriggerAnotherLoad() async throws {
        let samples = SignalStatus.allCases.map { status in
            SignalFixture.request(
                status: status, id: "ksreq_" + UUID().uuidString.replacing("-", with: "").lowercased()
            )
        }

        let open = try #require(samples.first { $0.status == .open })
        let recorder = SignalSuspendedTransport(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config")
            ],
            blockedIndex: 6,
            statusPages: try SignalFixture.statusPages(samples)
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client)
        let originalLoad = Task { await board.load() }

        await recorder.waitUntilBlocked()
        #expect(board.requests.isEmpty)
        #expect(board.isLoading)

        board.status = .open
        await board.load()
        await recorder.release()
        await originalLoad.value
        #expect(board.requests == [open])
        #expect(board.sectionCursors.isEmpty)
        #expect(board.error == nil)
        #expect(board.isLoading == false)

        let calls = await recorder.recorded()
        #expect(calls.count == 7)

        let queries = calls.filter { $0.url?.lastPathComponent == "requests" }.map { request in
            let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }

        #expect(queries.allSatisfy { $0["limit"] == "100" })
        #expect(Set(queries.prefix(5).compactMap { $0["status"] }) == Set(SignalStatus.allCases.map(\.rawValue)))

        board.status = nil
        #expect(board.requests.count == samples.count)
    }
}
