//
// SignalRequestText.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Presents a request title and description using the active translation and preview formatting.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalRequestText: View {
    let request: SignalRequest
    let translation: SignalTranslationModel
    let descriptionLineLimit: Int?
    var collapsesLineBreaks = false

    /// Collapses line breaks for compact previews while preserving them in the detail view.
    private func formattedText(_ text: String) -> String {
        collapsesLineBreaks ? text.replacing(/\s*\R\s*/, with: " ") : text
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(formattedText(translation.displayText(request.title)))
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(nil)

            Text(formattedText(translation.displayText(request.description)))
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(descriptionLineLimit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
