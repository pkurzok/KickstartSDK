//
// SignalTranslationStatusView.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Shows translation progress and recoverable errors without replacing the board or discussion.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalTranslationStatusView: View {
    let model: SignalTranslationModel

    var body: some View {
        if model.isTranslating {
            Section {
                ProgressView(String(localized: "Translating…", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
        }

        if model.error != nil {
            Section {
                Text("Some text could not be translated.", bundle: .module)

                Button(String(localized: "Try again", bundle: .module), systemImage: "arrow.clockwise") {
                    model.retry()
                }
            }
        }
    }
}
