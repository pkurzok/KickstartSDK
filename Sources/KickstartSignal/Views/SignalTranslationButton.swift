//
// SignalTranslationButton.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Offers translation into the preferred language or restores original text on supported platforms.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalTranslationButton: View {
    let model: SignalTranslationModel

    var body: some View {
        #if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
        Menu {
            if model.targetLanguage == nil {
                Button(String(localized: "Translate to \(model.preferredLanguageName)", bundle: .module)) {
                    model.start(target: model.preferredLanguage)
                }
            } else {
                Button(String(localized: "Show Original", bundle: .module)) {
                    model.showOriginal()
                }
            }
        } label: {
            Label(String(localized: "Translate", bundle: .module), systemImage: "translate")
        }
        .labelStyle(.iconOnly)
        #endif
    }
}
