//
// SignalContentLimits.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// Maximum submission lengths, measured in Unicode scalars.
struct SignalContentLimits: Codable {
    static let standard = SignalContentLimits(title: 80, description: 500, comment: 500)

    let title: Int
    let description: Int
    let comment: Int
}
