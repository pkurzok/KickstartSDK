//
// SignalBoardLoadingTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal board loading")
struct SignalBoardLoadingTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func failedInitialConfigurationCanBeRetried() async throws {
        let request = SignalFixture.request()

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                (Data(), 503),
                try SignalFixture.response("config")
            ],
            statusPages: try SignalFixture.statusPages([request])
        )
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) })

        let board = SignalBoardModel(client: client, status: .planned)

        await board.load()
        #expect(board.error != nil)
        #expect(board.requests.isEmpty)
        #expect(board.isLoading == false)

        await board.retry()
        #expect(board.error == nil)
        #expect(board.requests == [request])
        #expect(board.configuration != nil)
        #expect(await recorder.recorded().count == 8)

        await board.load()
        #expect(await recorder.recorded().count == 8)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func failedPaginationRetainsLoadedContentAndRetriesOnlyThatPage() async throws {
        let first = SignalFixture.request()
        let next = SignalFixture.request(id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 2)

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                (Data(), 503),
                try SignalFixture.encoded(SignalRequestPage(requests: [next], nextCursor: nil))
            ],
            statusPages: try SignalFixture.statusPages([first], cursors: [.planned: "existing-cursor"])
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let board = SignalBoardModel(client: client, status: .planned)

        await board.load()
        await board.loadMore(in: .planned)
        #expect(board.requests == [first])
        #expect(board.nextCursor == "existing-cursor")
        #expect(board.error != nil)
        #expect(board.isLoading == false)

        board.status = .completed
        await board.retry()
        #expect(board.requests.isEmpty)

        board.status = .planned
        #expect(board.requests == [next, first])
        #expect(board.nextCursor == nil)
        #expect(board.error == nil)

        let calls = await recorder.recorded()
        #expect(calls.count == 9)
        #expect(calls.count { $0.url?.lastPathComponent == "config" } == 1)
        for call in calls.suffix(2) {
            let url = try #require(call.url)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.contains(URLQueryItem(name: "status", value: "planned")))
            #expect(query.contains(URLQueryItem(name: "cursor", value: "existing-cursor")))
        }
    }
}
