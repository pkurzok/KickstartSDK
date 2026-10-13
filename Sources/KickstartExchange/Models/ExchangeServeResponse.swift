//
// ExchangeServeResponse.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

/// Contains an advertisement and the tokens needed for impression reporting.
struct ExchangeServeResponse {
    let serveID: String?
    let impressionToken: String?
    let ad: ExchangeServedAdResponse
}
