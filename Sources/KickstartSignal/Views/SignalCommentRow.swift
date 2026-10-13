//
// SignalCommentRow.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Displays a comment or developer reply with its date and any active translation.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalCommentRow: View {
    let comment: SignalComment
    let translation: SignalTranslationModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(translation.displayText(comment.body))

            Text(comment.createdAt, format: .dateTime.day().month(.abbreviated).year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
