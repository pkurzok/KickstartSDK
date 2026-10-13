//
// SignalTranslationFailureTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

#if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
import Foundation
import Testing
import Translation
@testable import KickstartSignal

@MainActor
@Suite("Signal translation failures")
struct SignalTranslationFailureTests {
    @available(iOS 18, macOS 15, *)
    @Test(arguments: [0, 1], [
        TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedLanguagePairing
    ])
    func unsupportedFieldsDoNotBlockOtherFields(failureIndex: Int, failure: TranslationError) async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        let texts = ["Bonjour", "Hola", "Danke"]
        var requested: [String] = []

        await model.translate(texts) { text in
            requested.append(text)
            if text == texts[failureIndex] { throw failure }
            return "Translated: " + text
        }

        #expect(requested == texts)
        for (index, text) in texts.enumerated() {
            #expect(model.displayText(text) == (index == failureIndex ? text : "Translated: " + text))
        }
        #expect(model.error != nil)
        #expect(model.isTranslating == false)
    }

    @available(iOS 18, macOS 15, *)
    @Test
    func unsupportedFieldsDoNotBlockNewContentOrRepeatWithoutRetry() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        await model.translate(["Unsupported", "Bonjour"]) { text in
            if text == "Unsupported" { throw TranslationError.unsupportedSourceLanguage }
            return "Hello"
        }
        let firstError = model.error
        var requested: [String] = []

        await model.translate(["Unsupported", "Bonjour", "Hola"]) { text in
            requested.append(text)
            return "Hello again"
        }

        #expect(requested == ["Hola"])
        #expect(model.displayText("Unsupported") == "Unsupported")
        #expect(model.displayText("Bonjour") == "Hello")
        #expect(model.displayText("Hola") == "Hello again")
        #expect(model.error == firstError)
        #expect(model.error != nil)
    }

    @available(iOS 18, macOS 15, *)
    @Test
    func explicitRetryReattemptsSkippedFieldsAndPreservesCompletedTranslations() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        await model.translate(["Unsupported", "Bonjour"]) { text in
            if text == "Unsupported" { throw TranslationError.unsupportedLanguagePairing }
            return "Hello"
        }
        model.retry()
        #expect(model.error == nil)
        var requested: [String] = []

        await model.translate(["Unsupported", "Bonjour"]) { text in
            requested.append(text)
            return "Recovered"
        }

        #expect(requested == ["Unsupported"])
        #expect(model.displayText("Unsupported") == "Recovered")
        #expect(model.displayText("Bonjour") == "Hello")
        #expect(model.error == nil)
    }

    @available(iOS 26, macOS 26, *)
    @Test(arguments: [
        TranslationError.unsupportedTargetLanguage, TranslationError.alreadyCancelled,
        TranslationError.notInstalled, TranslationError.internalError
    ])
    func sessionFailuresStopUntilExplicitRetry(failure: TranslationError) async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        var requested: [String] = []
        await model.translate(["Bonjour", "Hola"]) { text in
            requested.append(text)
            throw failure
        }
        #expect(requested == ["Bonjour"])
        #expect(model.error != nil)
        #expect(model.isTranslating == false)

        await model.translate(["Danke"]) { text in
            Issue.record("A session failure resumed without an explicit retry")
            return text
        }
        model.retry()
        await model.translate(["Bonjour", "Hola"]) { "Translated: " + $0 }
        #expect(model.displayText("Bonjour") == "Translated: Bonjour")
        #expect(model.displayText("Hola") == "Translated: Hola")
        #expect(model.error == nil)
    }
}
#endif
