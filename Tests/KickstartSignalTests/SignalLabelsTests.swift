//
// SignalLabelsTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@MainActor @Suite("Signal labels")
struct SignalLabelsTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func missingKeysUseTheSDKTranslations() {
        let labels = SignalLabels(bundle: SignalResources.bundle)
        #expect(labels.title == String(localized: "Feature Requests", bundle: SignalResources.bundle))
        #expect(labels.detailTitle == String(localized: "Request", bundle: SignalResources.bundle))
        #expect(labels.suggestionTitle == String(localized: "Suggest a Feature", bundle: SignalResources.bundle))
        #expect(labels.developerName == String(localized: "Developer", bundle: SignalResources.bundle))
        #expect(labels.confirmationMessage == String(
            localized: "Thanks for sharing your suggestion!", bundle: SignalResources.bundle
        ))
        #expect(labels.emptyStatusMessage == String(
            localized: "Nothing to see here yet.", bundle: SignalResources.bundle
        ))
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func appCatalogOverridesAllSixLabels() throws {
        let url = try #require(Bundle.module.url(forResource: "fr", withExtension: "lproj"))
        let bundle = try #require(Bundle(url: url))
        let labels = SignalLabels(bundle: bundle)
        #expect(labels.title == "Les idées de notre app")
        #expect(labels.detailTitle == "Votre idée")
        #expect(labels.suggestionTitle == "Partagez votre idée")
        #expect(labels.developerName == "Notre équipe")
        #expect(labels.confirmationMessage == "Merci de nous aider !")
        #expect(labels.emptyStatusMessage == "Aucune idée dans cette catégorie.")
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test
    func partialOverridesPreserveLiteralValuesAndUseDefaultsForMissingKeys() throws {
        let url = try #require(Bundle.module.url(forResource: "en", withExtension: "lproj"))
        let bundle = try #require(Bundle(url: url))
        let labels = SignalLabels(bundle: bundle)
        #expect(labels.title == "Ideas: 100% %@ **welcome**")
        #expect(labels.developerName.isEmpty)
        #expect(labels.detailTitle == String(localized: "Request", bundle: SignalResources.bundle))
        #expect(labels.suggestionTitle == String(localized: "Suggest a Feature", bundle: SignalResources.bundle))
        #expect(labels.confirmationMessage == String(
            localized: "Thanks for sharing your suggestion!", bundle: SignalResources.bundle
        ))
        #expect(labels.emptyStatusMessage == String(
            localized: "Nothing to see here yet.", bundle: SignalResources.bundle
        ))
    }
}
