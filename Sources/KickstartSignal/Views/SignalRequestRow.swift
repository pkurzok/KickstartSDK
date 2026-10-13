//
// SignalRequestRow.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Shows a compact request preview, its vote control or count, and a link to its discussion.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalRequestRow: View {
    let model: SignalDetailModel
    let translation: SignalTranslationModel
    let allowsVoting: Bool

    var body: some View {
        HStack {
            if allowsVoting {
                SignalVoteButton(model: model)
            } else {
                Text(model.request.voteCount, format: .number)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel(Text("\(model.request.voteCount) votes", bundle: .module))
            }

            NavigationLink(value: model.request) {
                SignalRequestText(
                    request: model.request, translation: translation,
                    descriptionLineLimit: 2, collapsesLineBreaks: true
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
        }
    }
}
