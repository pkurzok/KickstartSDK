//
// SignalComment.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A published comment or developer reply on a feature request.
struct SignalComment: Codable, Identifiable {
    let id: String
    let body: String
    let isDeveloper: Bool
    let createdAt: Date
}
