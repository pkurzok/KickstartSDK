//
// SignalDetailCommentTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal detail comments")
struct SignalDetailCommentTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func openingDetailsUsesLoadedContentAndLocalVoteWithoutNetwork(voted: Bool) async throws {
        let request = SignalFixture.request()

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config")
            ],
            statusPages: try SignalFixture.statusPages([request])
        )

        let identities = SignalIdentityStore(defaults: nil)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) })

        let board = SignalBoardModel(client: client, status: .planned)

        await board.load()
        #expect(board.configuration != nil)

        let detail = board.detailModel(for: request)
        #expect(detail.hasVoted == false)

        identities.setVote(voted, requestID: request.id)

        await detail.load(interactionsEnabled: false)
        #expect(detail.request == request)
        #expect(board.requests == [request])
        #expect(detail.hasVoted == voted)
        #expect(detail.error == nil)
        #expect(detail.isBusy == false)
        #expect(await recorder.recorded().map { $0.url?.path } == ["/signal/v1/sessions", "/signal/v1/config"]
            + Array(repeating: "/signal/v1/requests", count: 5))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func openingDetailsFetchesOnlyCommentsAndPreservesTheVoteOnFailure(fails: Bool) async throws {
        let request = SignalFixture.request()
        let comments = fails ? (Data(), 503) : try SignalFixture.response("list_comments")

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                comments
            ]
        )

        let identities = SignalIdentityStore(defaults: nil)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.loadConfiguration()
        identities.setVote(true, requestID: request.id)

        let detail = SignalDetailModel(request: request, client: client)
        await detail.load(interactionsEnabled: true)
        #expect(detail.request == request)
        #expect(detail.hasVoted)
        #expect((detail.commentsError != nil) == fails)
        #expect(detail.isBusy == false)
        #expect(detail.comments.map(\.body) == (fails ? [] : ["Folders would help organize my work."]))
        #expect(await recorder.recorded().map { $0.url?.path } == [
            "/signal/v1/sessions", "/signal/v1/config", "/signal/v1/requests/" + request.id + "/comments"
        ])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func votingPreservesInlineCommentSubmissionErrors(voteFails: Bool) async throws {
        let vote = voteFails ? (Data(), 503) : try SignalFixture.response("vote")
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            (Data(), 422),
            vote,
            try SignalFixture.response("create_comment")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)

        #expect(await detail.submitComment("Keep this draft", limit: 500) == false)
        #expect(detail.error == SignalError.invalidContent.localizedDescription)

        let voteError = await detail.toggleVote()
        #expect(voteError == (voteFails ? SignalError.server.localizedDescription : nil))
        #expect(detail.error == SignalError.invalidContent.localizedDescription)
        #expect(detail.hasVoted == (voteFails == false))
        #expect(detail.isBusy == false)

        #expect(await detail.submitComment("Keep this draft", limit: 500))
        #expect(detail.error == nil)
        #expect(detail.submissionMessage != nil)
        #expect(await recorder.recorded().count == 4)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func reopeningDetailsReplacesCommentsAndRestartsPagination() async throws {
        let previous = SignalComment(
            id: "kscom_" + String(repeating: "b", count: 32),
            body: "Previously loaded comment",
            isDeveloper: false,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.encoded(SignalCommentPage(comments: [previous], nextCursor: "next-page")),
            try SignalFixture.response("list_comments")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)

        await detail.load(interactionsEnabled: true)
        #expect(detail.comments.map(\.id) == [previous.id])
        #expect(detail.commentsCursor == "next-page")

        await detail.load(interactionsEnabled: true)
        #expect(detail.comments.map(\.body) == ["Folders would help organize my work."])
        #expect(detail.commentsCursor == nil)
        #expect(detail.commentsError == nil)
        #expect(detail.isBusy == false)

        let calls = await recorder.recorded()
        #expect(calls.count == 3)
        #expect(calls[1].url == calls[2].url)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func transportCancelledCommentLoadsPreserveContentAndClearBusyState(more: Bool) async {
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { request in
                if request.url?.path == "/signal/v1/sessions" {
                    return try SignalFixture.response("session")
                }

                throw CancellationError()
            }
        )
        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)
        let previous = SignalComment(
            id: "kscom_" + String(repeating: "b", count: 32),
            body: "Previously loaded comment",
            isDeveloper: false,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        detail.comments = [previous]
        detail.commentsCursor = "next-page"
        detail.commentsError = "Previous comment error"
        detail.error = "Previous comment submission error"

        if more {
            await detail.load(cursor: detail.commentsCursor)
        } else {
            await detail.load(interactionsEnabled: true)
        }

        #expect(detail.comments.map(\.id) == [previous.id])
        #expect(detail.commentsCursor == (more ? "next-page" : nil))
        #expect(detail.commentsError == nil)
        #expect(detail.error == "Previous comment submission error")
        #expect(detail.isBusy == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func commentPaginationRetryClearsTheErrorAndPreservesLoadedComments() async throws {
        let first = SignalComment(
            id: "kscom_" + String(repeating: "a", count: 32),
            body: "First comment",
            isDeveloper: false,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let second = SignalComment(
            id: "kscom_" + String(repeating: "b", count: 32),
            body: "Second comment",
            isDeveloper: true,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let firstPage = try SignalFixture.encoded(SignalCommentPage(comments: [first], nextCursor: "next-page"))
        let nextPage = try SignalFixture.encoded(SignalCommentPage(comments: [first, second], nextCursor: nil))

        let recorder = SignalSuspendedTransport(
            responses: [
                try SignalFixture.response("session"),
                firstPage,
                (Data(), 503),
                nextPage
            ],
            blockedIndex: 3
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)

        await detail.load(interactionsEnabled: true)
        #expect(detail.commentsError == nil)

        await detail.load(cursor: detail.commentsCursor)
        #expect(detail.commentsError != nil)
        #expect(detail.comments.map(\.id) == [first.id])
        #expect(detail.commentsCursor == "next-page")
        #expect(detail.isBusy == false)

        let retry = Task { await detail.load(cursor: detail.commentsCursor) }
        await recorder.waitUntilBlocked()
        #expect(detail.commentsError == nil)
        #expect(detail.isBusy)
        #expect(detail.comments.map(\.id) == [first.id])

        await recorder.release()
        await retry.value
        #expect(detail.commentsError == nil)
        #expect(detail.isBusy == false)
        #expect(detail.comments.map(\.id) == [first.id, second.id])
        #expect(detail.commentsCursor == nil)

        let calls = await recorder.recorded()
        #expect(calls.count == 4)
        #expect(calls[2].url == calls[3].url)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func firstCommentPageCanBeRetriedWithoutReloadingTheRequest() async throws {
        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                (Data(), 503),
                try SignalFixture.response("list_comments")
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let request = SignalFixture.request()
        let detail = SignalDetailModel(request: request, client: client)

        await detail.load(interactionsEnabled: true)
        #expect(detail.commentsError != nil)
        #expect(detail.error == nil)
        #expect(detail.comments.isEmpty)
        #expect(detail.isBusy == false)

        await detail.load(cursor: detail.commentsCursor)
        #expect(detail.commentsError == nil)
        #expect(detail.comments.count == 1)
        #expect(detail.request == request)

        let calls = await recorder.recorded()
        #expect(calls.map { $0.url?.path } == ["/signal/v1/sessions",
            "/signal/v1/requests/" + request.id + "/comments", "/signal/v1/requests/" + request.id + "/comments"])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func savedVoteIsLoadedBeforeCommentsFinishLoading() async throws {
        let recorder = SignalSuspendedTransport(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.response("config"),
                try SignalFixture.response("list_comments")
            ],
            blockedIndex: 2
        )

        let identities = SignalIdentityStore(defaults: nil)

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: identities,
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        _ = try await client.loadConfiguration()

        let request = SignalFixture.request()
        identities.setVote(true, requestID: request.id)

        let detail = SignalDetailModel(request: request, client: client)
        let loading = Task { await detail.load(interactionsEnabled: true) }

        await recorder.waitUntilBlocked()
        #expect(detail.hasVoted)
        #expect(detail.request == request)
        #expect(detail.isBusy)
        #expect(detail.isSubmittingComment == false)

        await recorder.release()
        await loading.value
        #expect(detail.isBusy == false)
        #expect(detail.error == nil)
        #expect(detail.comments.count == 1)
    }
}
