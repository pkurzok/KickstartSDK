//
// SignalTranslationModelTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor
@Suite("Inline Signal translation")
struct SignalTranslationModelTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func translationIsOptInAndBoardsAreIndependent() async {
        let model = SignalTranslationModel()
        await model.translate(["Bonjour"]) { _ in
            Issue.record("Translation ran before it was requested")
            return "Hello"
        }
        #expect(model.displayText("Bonjour") == "Bonjour")
        model.start(target: Locale.Language(identifier: "en"))
        await model.translate(["Bonjour"]) { _ in "Hello" }
        #expect(model.displayText("Bonjour") == "Hello")

        let anotherBoard = SignalTranslationModel()
        #expect(anotherBoard.targetLanguage == nil)
        anotherBoard.start(target: Locale.Language(identifier: "en"))
        #expect(anotherBoard.displayText("Bonjour") == "Bonjour")
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func fieldsKeepTheirOriginalTextAndTranslateIndependently() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        let originals = [
            "Titre", "Description\n\nDeux lignes.", "¡Buena idea!", "谢谢", "a", "字",
            "Titre", "\n\t ", "👍", "123", "!!!"
        ]
        var received: [String] = []
        await model.translate(originals) { text in
            received.append(text)
            return "Translated: " + text
        }
        #expect(received == Array(originals.prefix(6)))
        #expect(model.displayText(originals[1]) == "Translated: Description\n\nDeux lignes.")
        for text in ["\n\t ", "👍", "123", "!!!"] { #expect(model.displayText(text) == text) }
        model.showOriginal()
        for text in originals { #expect(model.displayText(text) == text) }
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func newlyLoadedOrEditedTextUsesTheSameChoiceWithoutRepeatingFinishedWork() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        await model.translate(["Titre"]) { _ in "Title" }
        #expect(model.displayText("Nouveau titre") == "Nouveau titre")

        var received: [String] = []
        await model.translate(["Titre", "Nouveau titre", "Un commentaire"]) { text in
            received.append(text)
            return "Translated: " + text
        }
        #expect(received == ["Nouveau titre", "Un commentaire"])
        #expect(model.displayText("Titre") == "Title")
        #expect(model.displayText("Nouveau titre") == "Translated: Nouveau titre")
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func showOriginalDiscardsAResultThatArrivesLater() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        let gate = SignalTranslationGate()
        let task = Task { await model.translate(["Titre"], using: gate.translate) }
        await gate.waitUntilStarted()
        model.showOriginal()
        gate.complete("Title")
        await task.value
        #expect(model.displayText("Titre") == "Titre")
        #expect(model.targetLanguage == nil)
        #expect(model.isTranslating == false)
        #expect(model.error == nil)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func changingTheTargetDiscardsTheOldResultAndCache() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        await model.translate(["Bonjour"]) { _ in "Hello" }
        let gate = SignalTranslationGate()
        let task = Task { await model.translate(["Titre"], using: gate.translate) }
        await gate.waitUntilStarted()
        model.start(target: Locale.Language(identifier: "es"))
        gate.complete("Title")
        await task.value
        #expect(model.displayText("Titre") == "Titre")
        #expect(model.displayText("Bonjour") == "Bonjour")
        await model.translate(["Titre"]) { _ in "Título" }
        #expect(model.displayText("Titre") == "Título")
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func navigationOverlapDoesNotLetAnOldRunClearOrOverwriteTheNewOne() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        let oldRun = UUID()
        let oldGate = SignalTranslationGate()
        let newGate = SignalTranslationGate()
        let oldTask = Task { await model.translate(["Titre"], runID: oldRun, using: oldGate.translate) }
        await oldGate.waitUntilStarted()
        let newTask = Task { await model.translate(["Commentaire"], using: newGate.translate) }
        await newGate.waitUntilStarted()
        model.cancel(runID: oldRun)
        oldGate.complete("Stale title")
        await oldTask.value
        #expect(model.isTranslating)
        #expect(model.displayText("Titre") == "Titre")
        newGate.complete("Comment")
        await newTask.value
        #expect(model.displayText("Commentaire") == "Comment")
        #expect(model.isTranslating == false)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func canceledTasksDoNotPublishAndCanResumeOnTheNextScreen() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        let gate = SignalTranslationGate()
        let task = Task { await model.translate(["Titre"], using: gate.translate) }
        await gate.waitUntilStarted()
        task.cancel()
        gate.complete("Canceled title")
        await task.value
        #expect(model.displayText("Titre") == "Titre")
        #expect(model.error == nil)
        #expect(model.isTranslating == false)
        await model.translate(["Titre"]) { _ in "Title" }
        #expect(model.displayText("Titre") == "Title")
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func aFailurePreservesCompletedFieldsAndWaitsForExplicitRetry() async {
        let model = SignalTranslationModel()
        model.start(target: Locale.Language(identifier: "en"))
        var received: [String] = []
        await model.translate(["Titre", "Description", "Commentaire"]) { text in
            received.append(text)
            if text == "Description" { throw CocoaError(.userCancelled) }
            return "Title"
        }
        #expect(received == ["Titre", "Description"])
        #expect(model.displayText("Titre") == "Title")
        #expect(model.displayText("Description") == "Description")
        #expect(model.error != nil)
        #expect(model.isTranslating == false)
        await model.translate(["Nouveau commentaire"]) { _ in
            Issue.record("An error restarted translation without an explicit retry")
            return "New comment"
        }
        model.retry()
        received = []
        await model.translate(["Titre", "Description", "Commentaire"]) { text in
            received.append(text)
            return "Translated: " + text
        }
        #expect(received == ["Description", "Commentaire"])
        #expect(model.error == nil)
    }
}
