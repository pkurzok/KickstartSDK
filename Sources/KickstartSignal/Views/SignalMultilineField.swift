//
// SignalMultilineField.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Edits multiline feedback while allowing Return to insert line breaks on macOS.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalMultilineField: View {
    @Binding var text: String
    let prompt: Text
    let lineLimit: ClosedRange<Int>

    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var lineHeight = 20.0
    #endif

    var body: some View {
        #if os(macOS)
        // A text editor lets Return insert a line break instead of ending field editing.
        VStack(alignment: .leading) {
            prompt.foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: lineHeight * Double(lineLimit.lowerBound))
                .accessibilityLabel(prompt)
        }
        #else
        TextField(text: $text, prompt: prompt, axis: .vertical) {
            prompt
        }
        .labelsHidden()
        .lineLimit(lineLimit)
        #endif
    }
}
