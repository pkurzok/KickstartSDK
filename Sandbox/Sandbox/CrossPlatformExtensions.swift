//
// CrossPlatformExtensions.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

extension View {
    func inlineNavigationBar() -> some View {
        #if os(macOS) || os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
