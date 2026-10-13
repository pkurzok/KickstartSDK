//
// PublicAPIFixture.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import KickstartSignal
import SwiftUI

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
struct SignalExternalView: View {
    var body: some View {
        NavigationStack {
            SignalBoardView(apiKey: "ks_live_" + String(repeating: "a", count: 43))
                .tint(.purple)
        }
        .kickstartPremiumUser(true)
    }

    func exerciseDemoAPI() {
        _ = NavigationStack {
            SignalBoardView.demo()
                .tint(.purple)
        }
        .kickstartPremiumUser(true)
    }
}
