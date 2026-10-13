//
// SandboxApp.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

//
// Exchange examples use the "preview" API key for sample adverts.
// Signal examples use an interactive in-memory demo board: no account,
// network connection, or App Store verification is needed. Each new
// demo board starts fresh; opening its detail screens preserves its state.
//

/// Demonstrates Kickstart Exchange placements and Kickstart Signal boards.
@main
struct SandboxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
