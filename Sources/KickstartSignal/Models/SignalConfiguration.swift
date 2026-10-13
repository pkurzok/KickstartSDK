//
// SignalConfiguration.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// The server's current interaction policy and submission limits for this app.
struct SignalConfiguration: Codable {
    let interactionsEnabled: Bool
    let limits: SignalContentLimits
}
