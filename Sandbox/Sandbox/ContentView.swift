//
// ContentView.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Lists the SDK's advertisement and feedback board examples.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Pinned to the bottom", value: SandboxDestination.pinnedBanner)
                    NavigationLink("Inside a scrolling list", value: SandboxDestination.scrollingBanner)
                    NavigationLink("With custom styling", value: SandboxDestination.styledBanner)
                } header: {
                    Text("Exchange")
                } footer: {
                    Text("These screens show an example advert.")
                }

                Section {
                    NavigationLink("Example board", value: SandboxDestination.signal)
                } header: {
                    Text("Signal")
                } footer: {
                    Text("""
                    This example board includes French and Spanish feedback so you can try the translation menu on \
                    iPhone, iPad, or Mac. Everything stays in memory.
                    """)
                }
            }
            .navigationTitle("Kickstart SDK")
            .navigationDestination(for: SandboxDestination.self) { destination in
                switch destination {
                case .pinnedBanner: PinnedBannerExample()
                case .scrollingBanner: ScrollingBannerExample()
                case .styledBanner: StyledBannerExample()
                case .signal: SignalBoardExample()
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    ContentView()
}
