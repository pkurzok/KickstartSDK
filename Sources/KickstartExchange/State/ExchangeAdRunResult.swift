//
// ExchangeAdRunResult.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

/// Represents the shared advertisement acquisition result for one app run.
enum ExchangeAdRunResult {
    case unavailable
    case advertisement(ExchangeAdPresentation)
}
