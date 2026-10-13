//
// SignalSubmissionTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal submissions")
struct SignalSubmissionTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func newIdeasRemainAvailableWhenCommentsAndVotingAreDisabled() async throws {
        let configuration = SignalConfiguration(
            interactionsEnabled: false,
            limits: .standard
        )
        let recorder = SignalTransportRecorder(responses: [
            try SignalFixture.response("session"),
            try SignalFixture.encoded(configuration),
            try SignalFixture.response("create_request")
        ])
        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let loaded = try await client.loadConfiguration()
        #expect(loaded.interactionsEnabled == false)

        let model = SignalSubmissionModel(client: client, limits: loaded.limits)
        model.title = "Folders"
        model.description = "Organize things"
        #expect(model.canSubmit)

        await model.submit()
        #expect(model.submitted)
        #expect(await recorder.recorded().count == 3)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func serverLimitsControlRequestAndCommentForms() async throws {
        let config = SignalConfiguration(
            interactionsEnabled: true,
            limits: SignalContentLimits(title: 2, description: 3, comment: 2)
        )

        let recorder = SignalTransportRecorder(
            responses: [
                try SignalFixture.response("session"),
                try SignalFixture.encoded(config)
            ]
        )

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let limits = try await client.loadConfiguration().limits
        let submission = SignalSubmissionModel(client: client, limits: limits)
        submission.title = "Hi"
        submission.description = "abc"
        #expect(submission.canSubmit)

        submission.title = "Hey"
        #expect(submission.canSubmit == false)

        await submission.submit()
        submission.title = "Hi"
        submission.description = "abcd"
        #expect(submission.canSubmit == false)

        submission.description = "abc"
        submission.title = "  "
        #expect(submission.canSubmit == false)

        // Two Unicode scalars, matching the server's code-point count.
        submission.title = "e\u{301}"
        #expect(submission.canSubmit)

        submission.title += "!"
        #expect(submission.canSubmit == false)

        let detail = SignalDetailModel(request: SignalFixture.request(), client: client)
        #expect(detail.canSubmitComment("Hi", limit: limits.comment))
        #expect(detail.canSubmitComment("Hey", limit: limits.comment) == false)
        #expect(detail.canSubmitComment("  ", limit: limits.comment) == false)
        #expect(detail.canSubmitComment("\n \n", limit: 500) == false)
        #expect((await detail.submitComment("Hey", limit: limits.comment)) == false)
        #expect(await recorder.recorded().count == 2)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func requestEditingStaysDisabledUntilSubmissionFinishes(fails: Bool) async throws {
        let response = fails ? (Data(), 503) : try SignalFixture.response("create_request")
        let recorder = SignalSuspendedTransport(
            responses: [try SignalFixture.response("session"), response], blockedIndex: 1
        )
        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { "fixture" },
            transport: { try await recorder.send($0) }
        )

        let model = SignalSubmissionModel(client: client, limits: SignalContentLimits.standard)

        model.title = "Folders"
        model.description = "Keep this draft\n\nWith a second paragraph.\nAnd another line."
        let sending = Task { await model.submit() }
        await recorder.waitUntilBlocked()
        // The form uses this state to disable editing and hide the back button.
        #expect(model.isSubmitting)
        #expect(model.canSubmit == false)
        #expect(model.submitted == false)

        await model.submit()
        #expect(model.isSubmitting)

        await recorder.release()
        await sending.value
        #expect(model.isSubmitting == false)
        #expect(model.submitted == (fails == false))
        #expect((model.error != nil) == fails)
        #expect(model.title == "Folders")
        #expect(model.description == "Keep this draft\n\nWith a second paragraph.\nAnd another line.")

        let calls = await recorder.recorded()
        #expect(calls.count == 2)

        let body = try SignalFixture.body(try #require(calls.last))
        #expect(body["title"] == model.title)
        #expect(body["description"] == model.description)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test(arguments: [false, true])
    func commentEditingStaysDisabledUntilSubmissionFinishes(fails: Bool) async throws {
        let response = fails ? (Data(), 503) : try SignalFixture.response("create_comment")

        let recorder = SignalSuspendedTransport(
            responses: [try SignalFixture.response("session"), response],
            blockedIndex: 1
        )

        let suite = "SignalTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))

        defer { defaults.removePersistentDomain(forName: suite) }

        let client = SignalClient(
            apiKey: SignalFixture.apiKey,
            identities: SignalIdentityStore(defaults: defaults),
            appTransaction: { "fixture"},
            transport: { try await recorder.send($0) }
        )

        let model = SignalDetailModel(request: SignalFixture.request(), client: client)
        let draft = "Keep this comment\n\nWith a second paragraph.\nAnd another line."
        let sending = Task { await model.submitComment(draft, limit: 500) }
        await recorder.waitUntilBlocked()
        // The comment field uses isBusy to disable editing until this request completes.
        #expect(model.isBusy)
        #expect(model.isSubmittingComment)
        #expect(model.canSubmitComment(draft, limit: 500) == false)
        #expect((await model.submitComment("Duplicate", limit: 500)) == false)
        #expect(model.isBusy)
        #expect(model.isSubmittingComment)

        await recorder.release()
        let succeeded = await sending.value
        #expect(succeeded == (fails == false))
        #expect(model.isBusy == false)
        #expect(model.isSubmittingComment == false)
        #expect((model.error != nil) == fails)
        #expect((model.submissionMessage != nil) == (fails == false))
        #expect(model.canSubmitComment(draft, limit: 500))

        let calls = await recorder.recorded()
        #expect(calls.count == 2)
        #expect(try SignalFixture.body(try #require(calls.last))["body"] == draft)
    }
}
