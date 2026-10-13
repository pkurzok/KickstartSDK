//
// View+SignalTranslation.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
extension View {
    /// Connects this screen's text to the board's shared translation state.
    ///
    /// - Parameters:
    ///   - model: The translation choice and cache shared by the board and its details.
    ///   - texts: Original fields to translate when translation is enabled.
    ///   - isActive: Whether this screen may schedule work; pass `false` while a destination covers it.
    func signalTranslation(
        model: SignalTranslationModel,
        texts: [String],
        isActive: Bool = true
    ) -> some View {
        #if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
        modifier(SignalTranslationModifier(model: model, texts: texts, isActive: isActive))
        #else
        self
        #endif
    }
}
