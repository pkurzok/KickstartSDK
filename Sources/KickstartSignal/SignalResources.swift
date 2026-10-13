//
// SignalResources.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// Lets tests inspect the SDK resource bundle instead of their own fixture bundle.
enum SignalResources {
    static let bundle: Bundle = .module
}
