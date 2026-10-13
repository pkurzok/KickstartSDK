//
// ScrollingBannerExample.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import KickstartExchange
import SwiftUI

/// Places a preview advertisement between rows of scrolling content.
/// The preview key does not record impressions. To test viewability tracking,
/// replace it with your registered app's API key. Scrolling records an impression
/// after the card is at least half visible for a full second, once per app run.
struct ScrollingBannerExample: View {
    var body: some View {
        List {
            Section {
                ForEach(1..<6) { row in
                    Text("Row \(row)")
                }
            }

            Section {
                ExchangeBannerAdView(apiKey: "preview")
                    .listRowInsets(.init(top: 2, leading: 2, bottom: 2, trailing: 2))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(6..<21) { row in
                    Text("Row \(row)")
                }
            }
        }
        .navigationTitle("In a list")
        .inlineNavigationBar()
    }
}

#Preview {
    NavigationStack {
        ScrollingBannerExample()
    }
}
