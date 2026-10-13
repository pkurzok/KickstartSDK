//
// SignalDemoTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Interactive Signal demo")
struct SignalDemoTests {
    private let requests = SignalStatus.allCases.enumerated().map { index, status in
        SignalFixture.request(
            votes: index * 10, status: status,
            id: "ksreq_" + String(repeating: String(index), count: 32), creationOrder: UInt64(index + 1)
        )
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func bundledDemoLoadsCommentsAndKeepsVotesWithinEachDemo() async throws {
        let client = SignalDemoData.makeClient()
        let board = SignalBoardModel(client: client)
        await board.load()

        #expect(board.error == nil)
        try #require(board.requests.isEmpty == false)

        for request in board.requests {
            let page = try await client.listComments(requestID: request.id)
            #expect(page.comments.contains { $0.isDeveloper })
        }

        let request = try #require(board.requests.first)
        let voted = try await client.vote(requestID: request.id, isPremium: true)
        #expect(voted.voteCount == request.voteCount + 1)
        #expect(client.hasVoted(requestID: request.id))

        let anotherDemo = SignalDemoData.makeClient()
        let anotherPage = try await anotherDemo.listRequests(status: request.status)
        let anotherRequest = try #require(anotherPage.requests.first { $0.id == request.id })
        #expect(anotherRequest.voteCount == request.voteCount)
        #expect(anotherDemo.hasVoted(requestID: request.id) == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func clientFiltersEachStatus() async throws {
        let client = SignalClient.demo(requests: requests)

        for status in SignalStatus.allCases {
            let page = try await client.listRequests(status: status)
            #expect(page.requests == requests.filter { $0.status == status })
            #expect(page.nextCursor == nil)
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func votesAreSharedBetweenBoardsAndRepeatedChangesAreIdempotent() async throws {
        let request = try #require(requests.last)
        let client = SignalClient.demo(requests: requests)
        let firstBoard = SignalBoardModel(client: client)
        await firstBoard.load()

        let detail = firstBoard.detailModel(for: request)
        await detail.toggleVote(isPremium: true)
        #expect(detail.hasVoted)
        #expect(detail.request.voteCount == request.voteCount + 1)
        #expect(firstBoard.requests.first?.voteCount == request.voteCount + 1)

        // Repeating a vote is idempotent, just like the live endpoint.
        let repeated = try await client.vote(requestID: request.id)
        #expect(repeated.voteCount == request.voteCount + 1)

        let secondBoard = SignalBoardModel(client: client)
        await secondBoard.load()
        let secondDetail = secondBoard.detailModel(for: request)
        #expect(secondDetail.hasVoted)
        #expect(secondDetail.request.voteCount == request.voteCount + 1)

        await secondDetail.toggleVote()
        #expect(secondDetail.hasVoted == false)
        #expect(secondDetail.request.voteCount == request.voteCount)

        let repeatedUndo = try await client.removeVote(requestID: request.id)
        #expect(repeatedUndo.voteCount == request.voteCount)

        let zeroVoteRequest = try #require(requests.first)
        #expect(try await client.removeVote(requestID: zeroVoteRequest.id).voteCount == 0)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func requestPagesKeepVoteOrderingAndCreationOrderTies() async throws {
        let olderOpen = SignalFixture.request(votes: 10, status: .open, creationOrder: 1)
        let newerOpen = SignalFixture.request(
            votes: 10, status: .open,
            id: "ksreq_" + String(repeating: "b", count: 32), creationOrder: 4
        )
        let planned = SignalFixture.request(
            votes: 30, status: .planned,
            id: "ksreq_" + String(repeating: "c", count: 32), creationOrder: 2
        )
        let completed = SignalFixture.request(
            votes: 1, status: .completed,
            id: "ksreq_" + String(repeating: "d", count: 32), creationOrder: 3
        )
        let inProgress = SignalFixture.request(
            votes: 20, status: .inProgress,
            id: "ksreq_" + String(repeating: "e", count: 32), creationOrder: 5
        )
        let client = SignalClient.demo(requests: [olderOpen, completed, newerOpen, planned, inProgress])

        let expected = [planned, inProgress, newerOpen, olderOpen, completed]
        let first = try await client.listRequests(limit: 2)
        let cursor = try #require(first.nextCursor)
        let second = try await client.listRequests(cursor: cursor, limit: 3)

        #expect(first.requests.count == 2)
        #expect(first.requests + second.requests == expected)
        #expect(second.nextCursor == nil)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func smallCommentThreadsLoadTogetherAndSubmissionsStayPrivate() async throws {
        let request = try #require(requests.first)

        let comments = (1...3).map { index in
            SignalComment(
                id: "kscom_" + String(repeating: String(index), count: 32),
                body: "Comment \(index)",
                isDeveloper: index == 2,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let client = SignalClient.demo(requests: requests, comments: [request.id: comments])
        let board = SignalBoardModel(client: client)
        await board.load()

        let detail = board.detailModel(for: request)
        await detail.load(interactionsEnabled: true)
        #expect(detail.comments.map(\.isDeveloper) == [false, true, false])
        #expect(detail.comments.map(\.id) == comments.map(\.id))
        #expect(detail.commentsCursor == nil)
        #expect(detail.commentsError == nil)
        #expect(await detail.submitComment("Great idea!", limit: 500, isPremium: true))
        #expect(detail.submissionMessage != nil)

        await detail.load(interactionsEnabled: true)
        #expect(detail.comments.map(\.id) == comments.map(\.id))

        let limits = try #require(board.configuration?.limits)
        let submission = SignalSubmissionModel(client: client, limits: limits)
        submission.title = "A new idea"
        submission.description = "Keep it private until it is reviewed."
        await submission.submit()

        #expect(submission.submitted)
        #expect(submission.error == nil)

        let page = try await client.listRequests()
        #expect(Set(page.requests.map(\.id)) == Set(requests.map(\.id)))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func receiptsAreIdempotentAndInvalidContentUsesNormalClientErrors() async throws {
        let client = SignalClient.demo(requests: requests)
        let key = UUID()
        let first = try await client.createRequest(title: "Folders", description: "", idempotencyKey: key)
        let retry = try await client.createRequest(title: "Folders", description: "", idempotencyKey: key)
        #expect(first.id == retry.id)
        #expect(first.hasVoted == true)
        #expect(retry.hasVoted == true)
        #expect(client.hasVoted(requestID: first.id))

        await #expect(throws: SignalError.invalidContent) {
            try await client.createRequest(title: "   ", description: "")
        }

        let request = try #require(requests.first)

        await #expect(throws: SignalError.invalidContent) {
            try await client.createComment(requestID: request.id, body: String(repeating: "a", count: 501))
        }

        await #expect(throws: SignalError.notFound) {
            try await client.listComments(requestID: "ksreq_" + String(repeating: "f", count: 32))
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func memoryIdentityIsStableAndStoresDoNotShareVotes() {
        let first = SignalIdentityStore(defaults: nil)
        let second = SignalIdentityStore(defaults: nil)
        #expect(first.identity() == first.identity())
        #expect(first.identity() != second.identity())

        first.setVote(true, requestID: "sample")
        #expect(first.votedIDs() == ["sample"])
        #expect(second.votedIDs().isEmpty)

        first.setVote(false, requestID: "sample")
        #expect(first.votedIDs().isEmpty)
    }
}
