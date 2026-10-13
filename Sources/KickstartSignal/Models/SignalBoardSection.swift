//
// SignalBoardSection.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

/// Published requests grouped under one status heading on the board.
struct SignalBoardSection: Identifiable {
    var id: SignalStatus { status }
    let status: SignalStatus
    let requests: [SignalRequest]
}
