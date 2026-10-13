//
// PremiumEnvironmentReader.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI
import KickstartSignal

@MainActor
struct PremiumEnvironmentReader: View {
    @Environment(\.kickstartPremiumUser) private var isPremium
    let probe: PremiumEnvironmentRecorder
    let name: String

    var body: some View {
        probe.values[name] = isPremium
        return Text(name)
    }
}
