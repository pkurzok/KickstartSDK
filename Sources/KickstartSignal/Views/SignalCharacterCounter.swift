//
// SignalCharacterCounter.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Displays the Unicode scalar count and highlights text that exceeds its submission limit.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalCharacterCounter: View {
    let text: String
    let limit: Int

    var body: some View {
        let count = text.unicodeScalars.count

        Text("\(count) / \(limit)", bundle: .module)
            .monospacedDigit()
            .accessibilityLabel(Text("\(count) of \(limit) characters", bundle: .module))
            .font(.caption)
            .foregroundStyle(count > limit ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
