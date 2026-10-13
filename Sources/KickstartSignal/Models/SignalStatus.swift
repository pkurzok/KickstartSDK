//
// SignalStatus.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// The developer's current decision about a feature request.
enum SignalStatus: String, Codable, CaseIterable, Identifiable {
    case open, inProgress = "in_progress", planned, completed, declined

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .open: String(localized: "Open", bundle: .module)
        case .planned: String(localized: "Planned", bundle: .module)
        case .inProgress: String(localized: "In Progress", bundle: .module)
        case .completed: String(localized: "Completed", bundle: .module)
        case .declined: String(localized: "Declined", bundle: .module)
        }
    }
}
