//
// SignalVerifiedSession.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// An app session cached in memory with a deadline for reusing its token.
struct SignalVerifiedSession {
    let token: String
    /// The early-renewal deadline used to avoid sending tokens close to their expiry.
    let expiresAt: Date
}
