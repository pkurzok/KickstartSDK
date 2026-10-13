//
// SignalContentValidationTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Signal content limits")
struct SignalContentValidationTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: ["x", "🍎", "e\u{301}"])
    func exactLimitsAllowUnicodeAndOverlongDraftsStayIntact(unit: String) async throws {
        let client = SignalClient.demo(requests: [SignalFixture.request()])
        let limits = try await client.loadConfiguration().limits
        #expect(limits.title == 80)
        #expect(limits.description == 500)
        #expect(limits.comment == 500)

        let title = String(repeating: unit, count: 80 / unit.unicodeScalars.count)
        let body = String(repeating: unit, count: 500 / unit.unicodeScalars.count)
        let submission = SignalSubmissionModel(client: client, limits: limits)
        submission.title = title
        submission.description = body

        #expect(submission.canSubmit)
        _ = try await client.createRequest(title: title, description: body)
        _ = try await client.createComment(requestID: SignalFixture.requestID, body: body)

        submission.title += "x"
        #expect(submission.canSubmit == false)

        await submission.submit()
        #expect(submission.title == title + "x")
        #expect(submission.submitted == false)

        submission.title = title
        submission.description += "x"
        #expect(submission.canSubmit == false)

        await submission.submit()
        #expect(submission.description == body + "x")

        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)
        #expect(detail.canSubmitComment(body, limit: limits.comment))
        #expect(detail.canSubmitComment(body + "x", limit: limits.comment) == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func formsCanUseHigherServerLimits() async throws {
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.response("create_request"),
            try SignalFixture.response("create_comment")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )
        let limits = SignalContentLimits(title: 100, description: 600, comment: 600)
        let model = SignalSubmissionModel(client: client, limits: limits)
        model.title = String(repeating: "x", count: 100)
        model.description = String(repeating: "x", count: 600)
        await model.submit()
        #expect(model.submitted)

        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)
        #expect(await detail.submitComment(String(repeating: "x", count: 600), limit: 600))
        #expect(await recorder.recorded().count == 3)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [413, 422])
    func serverCanRejectContentWithoutDiscardingTheDraft(status: Int) async throws {
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            (Data(#"{"error":"invalid_content"}"#.utf8), status)
        ])
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
        #expect(model.error == SignalError.invalidContent.localizedDescription)
        #expect(model.title == "Folders")
        #expect(model.description == "Organize things")
    }
}
