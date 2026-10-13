//
// SignalSessionResponse.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// The session token and lifetime returned after the server verifies the app.
struct SignalSessionResponse: Decodable {
    let sessionToken: String
    /// The token lifetime in seconds, before the client applies its early-renewal margin.
    let expiresIn: Int
}
