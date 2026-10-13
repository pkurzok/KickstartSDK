//
// SignalTranslationLanguageTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

#if canImport(NaturalLanguage) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
import Foundation
import Testing
@testable import KickstartSignal

@Suite("Signal same-language translation fallback")
struct SignalTranslationLanguageTests {
    @available(iOS 18, macOS 15, *)
    @Test(arguments: [
        "Read saved articles offline",
        "Export highlights as Markdown",
        "A widget for my reading queue",
        "Folders"
    ])
    func englishTitlesAreAlreadyInEnglish(text: String) {
        #expect(SignalTranslationLanguage.matches(text, target: Locale.Language(identifier: "en-GB")))
        #expect(SignalTranslationLanguage.matches(text, target: Locale.Language(identifier: "en-US")))
    }

    @available(iOS 18, macOS 15, *)
    @Test(arguments: ["Organiser ma bibliothèque en dossiers", "¡Buena idea!", "谢谢", ""])
    func foreignOrUnidentifiedTextDoesNotBecomeASameLanguageSuccess(text: String) {
        #expect(SignalTranslationLanguage.matches(text, target: Locale.Language(identifier: "en")) == false)
    }
}
#endif
