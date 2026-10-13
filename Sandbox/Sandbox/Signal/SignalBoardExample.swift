//
// SignalBoardExample.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import KickstartSignal
import SwiftUI

/// Presents the SDK board inside the sandbox's navigation stack.
struct SignalBoardExample: View {
    var body: some View {
        SignalBoardView.demo()
    }
}

#Preview {
    NavigationStack {
        SignalBoardExample()
    }
}
