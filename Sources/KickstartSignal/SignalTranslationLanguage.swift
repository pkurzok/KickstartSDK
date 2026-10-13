//
// SignalTranslationLanguage.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

#if canImport(NaturalLanguage) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
import Foundation
import NaturalLanguage

/// Recognizes content that is already written in a translation's target language.
@available(iOS 18, macOS 15, *)
enum SignalTranslationLanguage {
    /// Returns whether the detected language and script match the target.
    ///
    /// Used only after Translation rejects a language pairing, never to hide content from translation.
    static func matches(_ text: String, target: Locale.Language) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return false }

        let source = Locale.Language(identifier: language.rawValue)
        guard let sourceCode = source.languageCode, sourceCode == target.languageCode else { return false }
        return source.script == target.script
    }
}
#endif
