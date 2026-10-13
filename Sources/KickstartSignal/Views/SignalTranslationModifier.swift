//
// SignalTranslationModifier.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI
#if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
import Translation

/// Runs on-device translation for a screen while preserving its task configuration between toggles.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalTranslationModifier: ViewModifier {
    let model: SignalTranslationModel
    let texts: [String]
    /// Prevents a covered board from competing with the visible detail screen for translation work.
    var isActive = true

    @State private var configuration: TranslationSession.Configuration?
    @State private var runID: UUID?
    @State private var isVisible = false

    /// Attaches translation work on supported platforms and cancels this screen's run when it becomes inactive.
    func body(content: Content) -> some View {
        content
            .translationTask(isVisible && isActive && model.targetLanguage != nil ? configuration : nil) { session in
                guard isVisible, isActive, session.targetLanguage == model.targetLanguage else { return }

                let currentRun = UUID()
                runID = currentRun

                await model.translate(texts, runID: currentRun) { text in
                    do {
                        // Separate calls let each field have its own source language.
                        return try await session.translate(text).targetText
                    } catch TranslationError.unsupportedLanguagePairing {
                        if let target = session.targetLanguage,
                           SignalTranslationLanguage.matches(text, target: target) {
                            return text
                        }
                        throw TranslationError.unsupportedLanguagePairing
                    }
                }
            }
            .onAppear {
                isVisible = true
                configure()
            }
            .onChange(of: texts) { configure() }
            .onChange(of: model.revision) { configure() }
            .onChange(of: isActive) {
                if isActive == false, let runID { model.cancel(runID: runID) }
                configure()
            }
            .onDisappear {
                isVisible = false
                if let runID { model.cancel(runID: runID) }
            }
    }

    /// Schedules translation for the visible screen using the selected target language.
    ///
    /// Invalidating the retained configuration advances its version so repeated toggles restart the task.
    private func configure() {
        guard isVisible, isActive, let target = model.targetLanguage else { return }
        // Keep the version while showing originals; recreating an equal configuration does not restart the task.
        if configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = .init(source: nil, target: target)
        }
    }
}
#endif
