//
// SignalDetailModel.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Observation

/// Coordinates a request's comments and voting, reporting successful request changes to its board.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor @Observable
final class SignalDetailModel {
    let client: SignalClient
    var request: SignalRequest
    var comments: [SignalComment] = []
    var commentsCursor: String?
    var hasVoted = false
    var isBusy = false
    var isSubmittingComment = false
    /// Comment submission failures displayed inline in the request details.
    var error: String?
    var commentsError: String?
    var submissionMessage: String?

    private let onRequestChange: @MainActor (SignalRequest) -> Void
    private var commentKey = UUID()
    private var lastComment = ""

    /// Loaded comments written by the app developer.
    var developerReplies: [SignalComment] {
        comments.filter(\.isDeveloper)
    }

    /// Loaded comments submitted by users.
    var userComments: [SignalComment] {
        comments.filter { $0.isDeveloper == false }
    }

    /// Creates request state with its locally saved vote.
    init(
        request: SignalRequest,
        client: SignalClient,
        onRequestChange: @escaping @MainActor (SignalRequest) -> Void = { _ in }
    ) {
        self.request = request
        self.client = client
        self.onRequestChange = onRequestChange
        hasVoted = client.hasVoted(requestID: request.id)
    }

    /// Applies a successful request change and notifies the owning board.
    private func update(_ request: SignalRequest) {
        self.request = request
        onRequestChange(request)
    }

    /// Reconcile a refreshed board without replacing an action that is still in flight.
    func refresh(_ request: SignalRequest) {
        guard isBusy == false else { return }
        self.request = request
        hasVoted = client.hasVoted(requestID: request.id)
    }

    /// Replaces the first comment page or appends a later page without duplicating existing comments.
    /// Skips comment networking when interactions are disabled and exposes failures through `commentsError`.
    /// Once started, the read finishes for this model even if the calling view disappears.
    func load(interactionsEnabled: Bool = true, cursor: String? = nil) async {
        guard Task.isCancelled == false, isBusy == false else {
            return
        }

        isBusy = true
        defer { isBusy = false }

        commentsError = nil

        if cursor == nil {
            hasVoted = client.hasVoted(requestID: request.id)
        }

        guard interactionsEnabled else {
            return
        }

        commentsCursor = cursor

        await Task {
            await loadComments(cursor: cursor)
        }.value
    }

    /// Fetches one comment page and leaves its cursor available for retry if the request fails.
    private func loadComments(cursor: String?) async {
        do {
            let page = try await client.listComments(requestID: request.id, cursor: cursor)

            if cursor == nil {
                comments = page.comments
            } else {
                let existing = Set(comments.map(\.id))
                comments += page.comments.filter { existing.contains($0.id) == false }
            }

            commentsCursor = page.nextCursor
        } catch is CancellationError {
            // ignore
        } catch {
            self.commentsError = error.localizedDescription
        }
    }

    /// Adds or removes the saved vote, updating the request and board only after server confirmation.
    /// Returns a failure message for the initiating vote control without changing inline comment errors.
    @discardableResult
    func toggleVote(isPremium: Bool = false) async -> String? {
        guard isBusy == false else {
            return nil
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let updated = if hasVoted {
                try await client.removeVote(requestID: request.id)
            } else {
                try await client.vote(requestID: request.id, isPremium: isPremium)
            }

            hasVoted.toggle()
            update(updated)
        } catch is CancellationError {
            // safely ignore
        } catch {
            return error.localizedDescription
        }

        return nil
    }

    /// Checks that no action is busy and the nonblank body fits its scalar limit.
    func canSubmitComment(_ body: String, limit: Int) -> Bool {
        isBusy == false && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && body.unicodeScalars.count <= limit
    }

    /// Returns whether the server accepted the comment, without adding it to published comments locally.
    /// Unchanged comments reuse their idempotency key after failure; success resets the key.
    func submitComment(
        _ body: String,
        limit: Int,
        isPremium: Bool = false
    ) async -> Bool {
        guard canSubmitComment(body, limit: limit) else {
            return false
        }

        if lastComment != body {
            lastComment = body
            commentKey = UUID()
        }

        error = nil
        isBusy = true
        isSubmittingComment = true

        defer {
            isBusy = false
            isSubmittingComment = false
        }

        do {
            _ = try await client.createComment(
                requestID: request.id, body: body, isPremium: isPremium, idempotencyKey: commentKey
            )

            commentKey = UUID()
            lastComment = ""
            submissionMessage = String(
                localized: "Thank you! Your comment was sent to the developer for review.",
                bundle: .module
            )

            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
