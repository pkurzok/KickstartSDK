//
// View+KickstartPremiumUser.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

extension View {
    /// Shares the host app's premium status with Kickstart views in this view hierarchy.
    /// Signal snapshots it when a request, vote, or comment is submitted; it does not verify purchases.
    public func kickstartPremiumUser(_ isPremium: Bool) -> some View {
        environment(\.kickstartPremiumUser, isPremium)
    }
}
