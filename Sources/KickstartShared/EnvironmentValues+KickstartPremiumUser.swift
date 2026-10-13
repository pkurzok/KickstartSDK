//
// EnvironmentValues+KickstartPremiumUser.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

extension EnvironmentValues {
    /// Whether the host app considers this user a premium customer. Defaults to false.
    public var kickstartPremiumUser: Bool {
        get { self[KickstartPremiumUserKey.self] }
        set { self[KickstartPremiumUserKey.self] = newValue }
    }
}
