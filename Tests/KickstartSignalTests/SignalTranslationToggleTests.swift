//
// SignalTranslationToggleTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Signal translation toggling")
struct SignalTranslationToggleTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func repeatedTogglesReuseCompletedTranslationsImmediately() async {
        let model = SignalTranslationModel()
        let english = Locale.Language(identifier: "en")
        model.start(target: english)
        await model.translate(["Titre", "Description française"]) { "English: " + $0 }

        for _ in 0..<20 {
            model.showOriginal()
            #expect(model.displayText("Titre") == "Titre")
            #expect(model.displayText("Description française") == "Description française")
            model.start(target: english)
            #expect(model.displayText("Titre") == "English: Titre")
            #expect(model.displayText("Description française") == "English: Description française")
            await model.translate(["Titre", "Description française"]) { text in
                Issue.record("A display toggle translated completed text again")
                return text
            }
            #expect(model.error == nil)
            #expect(model.isTranslating == false)
        }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func togglingDuringWorkKeepsCompletedFieldsAndTranslatesOnlyMissingContent() async {
        let model = SignalTranslationModel()
        let english = Locale.Language(identifier: "en")
        model.start(target: english)
        await model.translate(["Titre"]) { _ in "Title" }
        let gate = SignalTranslationGate()
        let oldTask = Task { await model.translate(["Titre", "Description"], using: gate.translate) }
        await gate.waitUntilStarted()

        model.showOriginal()
        model.start(target: english)
        #expect(model.displayText("Titre") == "Title")
        var requested: [String] = []
        await model.translate(["Titre", "Description", "Nouveau commentaire"]) { text in
            requested.append(text)
            return "English: " + text
        }
        gate.complete("Stale description")
        await oldTask.value

        #expect(requested == ["Description", "Nouveau commentaire"])
        #expect(model.displayText("Titre") == "Title")
        #expect(model.displayText("Description") == "English: Description")
        #expect(model.displayText("Nouveau commentaire") == "English: Nouveau commentaire")
        #expect(model.error == nil)
        #expect(model.isTranslating == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func switchingLanguageAfterShowingOriginalDoesNotReuseThePreviousLanguage() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        await model.translate(["Titre"]) { _ in "Title" }
        model.showOriginal()
        model.start(target: Locale.Language(identifier: "es"))
        #expect(model.displayText("Titre") == "Titre")
        await model.translate(["Titre"]) { _ in "Título" }
        #expect(model.displayText("Titre") == "Título")
    }
}
