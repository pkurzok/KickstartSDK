//
// SignalLoadLifetimeTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

/// Covers retained models when SwiftUI cancels a disappearing screen's task.
@MainActor @Suite("Signal load lifetime")
struct SignalLoadLifetimeTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [0, 1, 6])
    func boardLoadSurvivesViewCancellation(blockedIndex: Int) async throws {
        let request = SignalFixture.request()
        let recorder = SignalSuspendedTransport(
            responses: [try SignalFixture.response("session"), try SignalFixture.response("config")],
            blockedIndex: blockedIndex,
            statusPages: try SignalFixture.statusPages([request])
        )
        let client = makeClient(recorder: recorder)
        let board = SignalBoardModel(client: client)

        // Suspend verification, configuration, or a status page before leaving the screen.
        let original = Task { await board.load() }
        await recorder.waitUntilBlocked()
        original.cancel()

        // Reappearing before the original read finishes must not leave an empty board.
        await board.load()
        #expect(board.isLoading)
        await recorder.release()
        await original.value

        #expect(board.configuration != nil)
        #expect(board.requests == [request])
        #expect(board.error == nil)
        #expect(board.isLoading == false)

        // A completed board does not load again, and overlapping callers do not duplicate the load.
        await board.load()
        let calls = await recorder.recorded()
        #expect(calls.count == 7)
        #expect(calls.count { $0.url?.lastPathComponent == "sessions" } == 1)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [3, 4])
    func detailLoadSurvivesViewCancellation(blockedIndex: Int) async throws {
        let recorder = SignalSuspendedTransport(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("config"),
            (Data(#"{"error":"verification_required"}"#.utf8), 403),
            try SignalFixture.response("session"),
            try SignalFixture.response("list_comments")
        ], blockedIndex: blockedIndex)
        let client = makeClient(recorder: recorder)
        _ = try await client.loadConfiguration()
        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)

        // The first comment request renews an existing session. Leave during renewal or the retried read.
        let original = Task { await detail.load() }
        await recorder.waitUntilBlocked()
        original.cancel()
        await detail.load()
        #expect(detail.isBusy)

        // Reopening does not allow mutations to overlap the read.
        await detail.toggleVote()
        #expect(await detail.submitComment("A comment", limit: 500) == false)

        await recorder.release()
        await original.value
        #expect(detail.comments.map(\.body) == ["Folders would help organize my work."])
        #expect(detail.commentsCursor == nil)
        #expect(detail.commentsError == nil)
        #expect(detail.error == nil)
        #expect(detail.isBusy == false)

        let calls = await recorder.recorded()
        #expect(calls.count == 5)
        #expect(calls.count { $0.url?.lastPathComponent == "sessions" } == 2)
        #expect(calls.filter { $0.url?.lastPathComponent == "comments" }.allSatisfy { $0.httpMethod == "GET" })
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func failedBoardLoadAfterViewCancellationCanBeRetried() async throws {
        let request = SignalFixture.request()
        let recorder = SignalSuspendedTransport(
            responses: [
                try SignalFixture.response("session"), (Data(), 503), try SignalFixture.response("config")
            ],
            blockedIndex: 0,
            statusPages: try SignalFixture.statusPages([request])
        )
        let board = SignalBoardModel(client: makeClient(recorder: recorder))
        let original = Task { await board.load() }
        await recorder.waitUntilBlocked()
        original.cancel()
        await board.load()
        await recorder.release()
        await original.value

        #expect(board.error != nil)
        #expect(board.isLoading == false)
        #expect(board.requests.isEmpty)

        await board.retry()
        #expect(board.error == nil)
        #expect(board.requests == [request])
        #expect(board.isLoading == false)
        let calls = await recorder.recorded()
        #expect(calls.count == 8)
        #expect(calls.count { $0.url?.lastPathComponent == "sessions" } == 1)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func failedDetailLoadAfterViewCancellationCanBeRetried() async throws {
        let recorder = SignalSuspendedTransport(responses: [
            try SignalFixture.response("session"), (Data(), 503), try SignalFixture.response("list_comments")
        ], blockedIndex: 0)
        let detail = SignalDetailModel(request: SignalFixture.request(), client: makeClient(recorder: recorder))
        let original = Task { await detail.load() }
        await recorder.waitUntilBlocked()
        original.cancel()
        await detail.load()
        await recorder.release()
        await original.value

        #expect(detail.commentsError != nil)
        #expect(detail.isBusy == false)
        #expect(detail.comments.isEmpty)

        await detail.load(cursor: detail.commentsCursor)
        #expect(detail.commentsError == nil)
        #expect(detail.comments.count == 1)
        #expect(detail.isBusy == false)
        let calls = await recorder.recorded()
        #expect(calls.count == 3)
        #expect(calls.count { $0.url?.lastPathComponent == "sessions" } == 1)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func alreadyCancelledLoadsDoNotStartRequests() async {
        let recorder = SignalSuspendedTransport(responses: [], blockedIndex: -1)
        let client = makeClient(recorder: recorder)
        let board = SignalBoardModel(client: client)
        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)

        // Main-actor tasks cannot begin until this method yields, making cancellation deterministic.
        let boardLoad = Task { await board.load() }
        boardLoad.cancel()
        await boardLoad.value
        let detailLoad = Task { await detail.load() }
        detailLoad.cancel()
        await detailLoad.value

        #expect(await recorder.recorded().isEmpty)
        #expect(board.configuration == nil)
        #expect(board.error == nil)
        #expect(board.isLoading == false)
        #expect(detail.commentsError == nil)
        #expect(detail.isBusy == false)
    }

    /// Mimics cancellation-aware URLSession reads while allowing tests to release each suspended response.
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    private func makeClient(recorder: SignalSuspendedTransport) -> SignalClient {
        SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { request in
                let response = try await recorder.send(request)
                try Task.checkCancellation()
                return response
            }
        )
    }
}
