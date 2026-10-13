//
// SignalRequestPage.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A page of published feature requests matching the requested sort and filters.
struct SignalRequestPage: Codable {
    let requests: [SignalRequest]
    /// An opaque continuation cursor, or `nil` when there are no more matching requests.
    let nextCursor: String?
}
