//
// SignalError.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// Signal failures mapped to localized messages suitable for displaying in the feedback UI.
enum SignalError: Error, LocalizedError, Equatable {
    case invalidConfiguration, appVerification, unavailable, notFound, invalidContent
    case rateLimited, connection, server, invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            String(
                localized: "Feedback is not configured correctly. Please contact the app developer.",
                bundle: .module
            )
        case .appVerification:
            String(
                localized: "There was a problem verifying the app; please try again later.",
                bundle: .module
            )
        case .unavailable:
            String(localized: "Feedback is unavailable right now.", bundle: .module)
        case .notFound:
            String(localized: "This request is no longer available.", bundle: .module)
        case .invalidContent:
            String(localized: "Check the length and contents of your submission.", bundle: .module)
        case .rateLimited:
            String(localized: "You have made several requests recently. Please try again later.", bundle: .module)
        case .connection:
            String(localized: "Could not connect. Check your connection and try again.", bundle: .module)
        case .server:
            String(localized: "Feedback could not be loaded. Please try again later.", bundle: .module)
        case .invalidResponse:
            String(localized: "The feedback service returned an unexpected response.", bundle: .module)
        }
    }
}
