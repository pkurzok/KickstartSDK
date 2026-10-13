//
// CrossPlatformExtensions.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
extension View {
    package func dismissesKeyboardOnScroll() -> some View {
        #if os(visionOS)
        self
        #else
        self.scrollDismissesKeyboard(.interactively)
        #endif
    }

    package func inlineNavigationBar() -> some View {
        #if os(macOS) || os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
