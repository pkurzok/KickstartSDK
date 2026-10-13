//
// SignalCommentRetryTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal comment retries")
struct SignalCommentRetryTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func failedFirstPageRefreshRetriesWithoutThePreviousPaginationCursor() async throws {
        let previous = SignalComment(
            id: "kscom_" + String(repeating: "a", count: 32),
            body: "Previously loaded comment",
            isDeveloper: false,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.encoded(SignalCommentPage(comments: [previous], nextCursor: "next-page")),
            (Data(), 503),
            try SignalFixture.response("list_comments")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)

        await detail.load()
        #expect(detail.commentsCursor == "next-page")

        // Reopening a cached detail model refreshes its first page without a cursor.
        await detail.load()
        #expect(detail.commentsError != nil)
        #expect(detail.comments.map(\.id) == [previous.id])
        #expect(detail.commentsCursor == nil)
        #expect(detail.isBusy == false)

        // Try again must retry that first page, not append the previously available next page.
        await detail.load(cursor: detail.commentsCursor)
        let calls = await recorder.recorded()
        try #require(calls.count == 4)
        #expect(calls[2].url == calls[3].url)
        #expect(detail.commentsError == nil)
        #expect(detail.commentsCursor == nil)
        #expect(detail.comments.map(\.body) == ["Folders would help organize my work."])
        #expect(detail.isBusy == false)
    }
}
