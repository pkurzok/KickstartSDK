//
// SignalRequest.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A published feature request with its vote count and developer-assigned status.
/// This installation's vote is stored separately by `SignalIdentityStore`.
struct SignalRequest: Codable, Identifiable, Hashable {
    let id: String
    /// Stable order within this app. Larger values sort first when ranks tie.
    let creationOrder: UInt64
    let title: String
    let description: String
    let status: SignalStatus
    let voteCount: Int
    let updatedAt: Date

    /// Orders requests by votes, placing newer requests first when vote counts tie.
    static func mostVotedFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.voteCount != rhs.voteCount {
            return lhs.voteCount > rhs.voteCount
        }

        return lhs.creationOrder > rhs.creationOrder
    }
}
