//
// SignalErrorResponse.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

/// The server error code used to classify a failed HTTP response.
struct SignalErrorResponse: Decodable {
    let error: String?
}
