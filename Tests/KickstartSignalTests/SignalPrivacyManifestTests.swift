//
// SignalPrivacyManifestTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

@Suite("Signal privacy manifest")
struct SignalPrivacyManifestTests {
    @Test
    func packagedEnglishLocalizationIncludesSingularAndPluralVotes() {
        let singular = 1
        let multiple = 2

        let english = Locale(identifier: "en")
        #expect(String(localized: "\(singular) votes", bundle: SignalResources.bundle, locale: english) == "1 vote")
        #expect(String(localized: "\(multiple) votes", bundle: SignalResources.bundle, locale: english) == "2 votes")
    }

    @Test
    func declaresOnlySignalDataAndOwnAppDefaults() throws {
        let url = try #require(SignalResources.bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))

        let data = try Data(contentsOf: url)
        let manifest = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)

        let declarations = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        #expect(Set(declarations.compactMap { $0["NSPrivacyCollectedDataType"] as? String }) == [
            "NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeOtherUserContent", "NSPrivacyCollectedDataTypePurchaseHistory"
        ])

        for declaration in declarations {
            #expect(declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
            #expect(declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            let purposes = declaration["NSPrivacyCollectedDataTypePurposes"] as? [String]
            #expect(purposes == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }

        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(accessed.count == 1)
        #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
