//
// SignalLabels.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// Uses app translations when present, falling back to the SDK's localized defaults.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalLabels {
    let title: String
    let detailTitle: String
    let suggestionTitle: String
    let developerName: String
    let confirmationMessage: String
    let emptyStatusMessage: String

    /// Resolves the host app's `Signal.*` localization keys, falling back to SDK translations.
    /// - Parameter bundle: The bundle containing the app's optional label overrides.
    init(bundle: Bundle = .main) {
        title = bundle.localizedString(
            forKey: "Signal.Title", value: String(localized: "Feature Requests", bundle: .module), table: nil
        )

        detailTitle = bundle.localizedString(
            forKey: "Signal.DetailTitle", value: String(localized: "Request", bundle: .module), table: nil
        )

        suggestionTitle = bundle.localizedString(
            forKey: "Signal.SuggestionTitle", value: String(localized: "Suggest a Feature", bundle: .module), table: nil
        )

        developerName = bundle.localizedString(
            forKey: "Signal.DeveloperName", value: String(localized: "Developer", bundle: .module), table: nil
        )

        confirmationMessage = bundle.localizedString(
            forKey: "Signal.ConfirmationMessage",
            value: String(localized: "Thanks for sharing your suggestion!", bundle: .module), table: nil
        )

        emptyStatusMessage = bundle.localizedString(
            forKey: "Signal.EmptyStatusMessage",
            value: String(localized: "Nothing to see here yet.", bundle: .module), table: nil
        )
    }
}
