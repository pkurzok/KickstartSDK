//
// SignalBoardStatusTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Signal board status browsing")
struct SignalBoardStatusTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func anEmptyBoardIsLoadedOnlyOnce() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config")
            ],
            statusPages: try SignalFixture.statusPages([])
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client)
        await board.load()

        for status in SignalStatus.allCases {
            board.status = status
            #expect(board.requests.isEmpty)
            await board.load()
        }

        board.status = nil
        await board.load()
        #expect(board.sections.isEmpty)
        #expect(board.error == nil)
        #expect(board.isLoading == false)
        #expect(await recorder.recorded().count == 7)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [SignalStatus.open, .inProgress, .planned, .completed])
    func eachChoiceShowsOnlyItsExactStatus(status: SignalStatus) async {
        let samples = SignalStatus.allCases.enumerated().map { index, status in
            SignalFixture.request(
                status: status, id: "ksreq_" + String(repeating: String(index), count: 32),
                creationOrder: UInt64(index + 1)
            )
        }

        let board = SignalBoardModel(client: .demo(requests: samples), status: status)
        await board.load()
        #expect(board.error == nil)
        #expect(board.requests == samples.filter { $0.status == status })
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func changingStatusPreservesPaginationWithoutAnyNetworkCalls() async throws {
        let first = SignalFixture.request(status: .open)
        let second = SignalFixture.request(status: .open, id: "ksreq_" + String(repeating: "b", count: 32))
        let planned = SignalFixture.request(status: .planned, id: "ksreq_" + String(repeating: "c", count: 32))

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                try SignalFixture.encoded(SignalRequestPage(requests: [second], nextCursor: "open-page-3"))
            ],
            statusPages: try SignalFixture.statusPages([first, planned], cursors: [.open: "open-page-2"])
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: .open)
        await board.load()
        await board.loadMore(in: .open)
        #expect(board.requests.count == 2)

        let callsBeforeSwitching = await recorder.recorded().count
        let row = board.detailModel(for: first)
        board.status = .planned
        #expect(board.requests == [planned])
        #expect(board.nextCursor == nil)

        board.status = .open
        #expect(Set(board.requests.map(\.id)) == [first.id, second.id])
        #expect(board.nextCursor == "open-page-3")
        #expect(board.detailModel(for: first) === row)

        board.status = nil
        #expect(board.requests.count == 3)
        #expect(board.sections.map(\.status) == [.open, .planned])

        // Reappearing after navigation must not start another load either.
        await board.load()
        #expect(board.error == nil)
        #expect(board.isLoading == false)

        let calls = await recorder.recorded()
        #expect(calls.count == callsBeforeSwitching)
        #expect(calls.count { $0.url?.lastPathComponent == "config" } == 1)

        let queries = try calls.dropFirst(2).map { request in
            let url = try #require(request.url)
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }

        #expect(queries.count == SignalStatus.allCases.count + 1)
        #expect(Set(queries.dropLast().compactMap { $0["status"] }) == Set(SignalStatus.allCases.map(\.rawValue)))
        #expect(queries.allSatisfy { $0["sort"] == "votes" && $0["limit"] == "100" })
        #expect(queries.last?["status"] == "open")
        #expect(queries.last?["cursor"] == "open-page-2")
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [SignalStatus.open, nil])
    func voteResponseWithANewStatusUpdatesTheVisibleSections(status: SignalStatus?) async throws {
        let open = SignalFixture.request(status: .open)
        let planned = SignalFixture.request(votes: 4, status: .planned)

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.encoded(planned)
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: status)
        board.allRequests = [open]
        let detail = board.detailModel(for: open)
        await detail.toggleVote()

        #expect(detail.request == planned)
        #expect(detail.error == nil)

        if status == nil {
            #expect(board.requests == [planned])
            #expect(board.sections.map(\.status) == [.planned])
        } else {
            #expect(board.requests.isEmpty)
            #expect(board.sections.isEmpty)
        }

        board.status = .planned
        #expect(board.requests == [planned])
        #expect(board.detailModel(for: planned) === detail)
        #expect(detail.hasVoted)
        #expect(await recorder.recorded().count == 2)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func allGroupsRequestsByStatusAndKeepsVoteOrderingWithinSections() {
        let samples = SignalStatus.allCases.enumerated().map { index, status in
            SignalFixture.request(
                votes: index + 1, status: status,
                id: "ksreq_" + String(repeating: String(index), count: 32), creationOrder: UInt64(index + 1)
            )
        }

        let newerOpen = SignalFixture.request(
            votes: 1, status: .open, id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 6
        )

        let popularOpen = SignalFixture.request(
            votes: 12, status: .open, id: "ksreq_" + String(repeating: "c", count: 32), creationOrder: 7
        )

        let board = SignalBoardModel(client: .demo(requests: []))
        board.allRequests = samples + [newerOpen, popularOpen]

        #expect(board.sections.map(\.status) == [.open, .inProgress, .planned, .completed, .declined])
        #expect(board.sections.first?.requests == [popularOpen, newerOpen, samples[0]])

        let grouped = board.sections.flatMap(\.requests)
        #expect(grouped.count == samples.count + 2)
        #expect(Set(grouped.map(\.id)) == Set(board.requests.map(\.id)))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [SignalStatus.open, .inProgress, .planned, .completed, .declined, nil])
    func allOmitsEmptyStatusSections(status: SignalStatus?) {
        let samples = status.map { [SignalFixture.request(status: $0)] } ?? []
        let board = SignalBoardModel(client: .demo(requests: []))
        board.allRequests = samples
        #expect(board.sections.map(\.status) == status.map { [$0] } ?? [])
        #expect(board.sections.flatMap(\.requests) == samples)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func loadedRequestsFilterImmediatelyByStatusAndKeepVoteOrdering() {
        let older = SignalFixture.request(votes: 3, status: .open)

        let newer = SignalFixture.request(
            votes: 3, status: .open, id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 2
        )

        let planned = SignalFixture.request(status: .planned, id: "ksreq_" + String(repeating: "c", count: 32))
        let board = SignalBoardModel(client: .demo(requests: []), status: .open)
        board.allRequests = [older, planned, newer]
        #expect(board.requests == [newer, older])

        board.status = .planned
        #expect(board.requests == [planned])

        board.status = .completed
        #expect(board.requests.isEmpty)
    }
}
