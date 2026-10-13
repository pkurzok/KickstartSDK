//
// SignalSubmissionModel.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Observation

/// Validates and submits a request draft while preserving its idempotency key across unchanged retries.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor @Observable
final class SignalSubmissionModel {
    var title = ""
    var description = ""
    var isSubmitting = false
    var submitted = false
    var error: String?
    let client: SignalClient
    let limits: SignalContentLimits

    private var key = UUID()
    private var lastContent: [String] = []

    /// Creates a draft using the board's server-provided title and description limits.
    init(client: SignalClient, limits: SignalContentLimits) {
        self.client = client
        self.limits = limits
    }

    /// Whether the title is nonblank, both fields fit their Unicode scalar limits, and no submission is active.
    var canSubmit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && title.unicodeScalars.count <= limits.title
            && description.unicodeScalars.count <= limits.description
            && isSubmitting == false
    }

    /// Submits a valid draft and records acceptance or a user-facing error.
    /// Changes to the title or description start a new idempotent submission; cancellation stays silent.
    func submit(isPremium: Bool = false) async {
        guard canSubmit else { return }

        if lastContent != [title, description] {
            key = UUID()
            lastContent = [title, description]
        }

        isSubmitting = true
        error = nil

        defer {
            isSubmitting = false
        }

        do {
            _ = try await client.createRequest(
                title: title, description: description, isPremium: isPremium, idempotencyKey: key
            )
            submitted = true
        } catch is CancellationError {
            // We can safely ignore these.
        } catch {
            self.error = error.localizedDescription
        }
    }
}
