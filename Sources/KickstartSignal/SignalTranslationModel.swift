//
// SignalTranslationModel.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Observation
#if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
import Translation
#endif

/// Shares a board's translation choice, cached text, progress, and errors with its request details.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor @Observable
final class SignalTranslationModel {
    let preferredLanguage: Locale.Language
    private(set) var targetLanguage: Locale.Language?
    private(set) var revision = 0
    private(set) var isTranslating = false
    private(set) var error: String?
    private var translations: [String: String] = [:]

    @ObservationIgnored private var activeRun: UUID?
    @ObservationIgnored private var translatedLanguage: Locale.Language?
    @ObservationIgnored private var skippedTexts = Set<String>()
    @ObservationIgnored private var isPaused = false

    var preferredLanguageName: String {
        let code = preferredLanguage.languageCode?.identifier ?? preferredLanguage.minimalIdentifier
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// Creates translation state with translation disabled and the supplied or device-preferred target language.
    init(preferredLanguage: Locale.Language = Locale.Language(
        identifier: Locale.preferredLanguages.first ?? Locale.current.identifier
    )) {
        self.preferredLanguage = preferredLanguage
    }

    /// Enables translation into the target language and requests a new run.
    ///
    /// Completed translations are reused when the target is unchanged and discarded when it changes.
    func start(target: Locale.Language) {
        if translatedLanguage != target {
            translations = [:]
            translatedLanguage = target
        }

        targetLanguage = target
        retry()
    }

    /// Displays original text and ignores pending results, keeping completed translations for reuse.
    func showOriginal() {
        targetLanguage = nil
        retry()
    }

    /// Requests a new run, clearing failures and skipped fields while preserving completed translations.
    func retry() {
        activeRun = nil
        skippedTexts = []
        isPaused = false
        isTranslating = false
        error = nil
        revision += 1
    }

    /// Returns the cached translation when translation is enabled, or the original text otherwise.
    func displayText(_ original: String) -> String {
        guard targetLanguage != nil else { return original }
        return translations[original] ?? original
    }

    /// Discards further results from the matching run without interrupting a newer run.
    func cancel(runID: UUID) {
        guard activeRun == runID else { return }
        activeRun = nil
        isTranslating = false
    }

    /// Translates uncached fields sequentially while the current translation choice remains active.
    ///
    /// Duplicate fields and text without letters are skipped. Unsupported source languages or pairings
    /// leave that field original and allow the run to continue; other failures pause work until retry.
    /// Canceled or superseded runs cannot publish late results.
    ///
    /// - Parameters:
    ///   - texts: Original fields to consider for translation.
    ///   - runID: Identifies the run so its view can discard pending results when it disappears.
    ///   - operation: Translates one field, allowing each field to have its own source language.
    ///     Transferred for sequential use; callers must not reuse its non-Sendable captures afterward.
    func translate(
        _ texts: [String], runID: UUID = UUID(),
        using operation: sending (String) async throws -> String
    ) async {
        // Session failures wait for an explicit retry, avoiding repeated download prompts.
        guard targetLanguage != nil, isPaused == false, Task.isCancelled == false else { return }

        var seen = Set<String>()

        let pending = texts.filter {
            guard $0.contains(where: \.isLetter), translations[$0] == nil, skippedTexts.contains($0) == false else {
                return false
            }

            return seen.insert($0).inserted
        }

        guard pending.isEmpty == false else { return }

        let currentRevision = revision
        activeRun = runID
        isTranslating = true

        defer {
            if activeRun == runID {
                activeRun = nil
                isTranslating = false
            }
        }

        for text in pending {
            guard activeRun == runID, revision == currentRevision, Task.isCancelled == false else { return }
            do {
                let translated = try await operation(text)
                guard activeRun == runID, revision == currentRevision, Task.isCancelled == false else { return }
                translations[text] = translated
            } catch {
                guard activeRun == runID, revision == currentRevision, Task.isCancelled == false else { return }
                self.error = error.localizedDescription
                #if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
                switch error {
                case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedLanguagePairing:
                    // One unsupported field must not prevent the remaining content from translating.
                    skippedTexts.insert(text)
                    continue
                default:
                    break
                }
                #endif
                isPaused = true
                return
            }
        }
    }
}
