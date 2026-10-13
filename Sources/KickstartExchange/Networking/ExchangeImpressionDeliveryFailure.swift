//
// ExchangeImpressionDeliveryFailure.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

/// Classifies failures while recording an advertisement impression.
enum ExchangeImpressionDeliveryFailure: Error, Equatable {
    case transport
    case server
    case unexpectedResponse
}
