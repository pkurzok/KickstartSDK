//
// SignalCommentPage.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A page of published comments and developer replies for one request.
struct SignalCommentPage: Codable {
    let comments: [SignalComment]
    /// An opaque continuation cursor, or `nil` when there are no more comments.
    let nextCursor: String?
}
