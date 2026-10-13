//
// SignalSubmission.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A receipt for private feedback. Submission does not publish the content.
struct SignalSubmission: Codable {
    let id: String

    /// The submitting installation's current vote, absent for comments and older servers.
    let hasVoted: Bool?
}
