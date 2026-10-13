//
// SignalBoardView.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// A complete native feedback board. Place it inside your app's `NavigationStack`.
/// Use an unbound stack or a `NavigationPath` binding to support the board's destination types.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
public struct SignalBoardView: View {
    @State private var model: SignalBoardModel
    private let labels = SignalLabels()

    /// Creates a board for the app identified by its Kickstart dashboard API key.
    ///
    /// Loading starts when the view appears.
    /// - Parameter apiKey: The app API key shared by Signal and Exchange.
    public init(apiKey: String) {
        self.init(client: SignalClient(apiKey: apiKey))
    }

    /// Creates independent board state around a live or in-memory client.
    private init(client: SignalClient) {
        _model = State(initialValue: SignalBoardModel(client: client))
    }

    /// An interactive sample board that keeps changes in memory and makes no network requests.
    /// Each new board has independent demo state, retained for the lifetime of its view state.
    public static func demo() -> Self {
        Self(client: SignalDemoData.makeClient())
    }

    public var body: some View {
        SignalBoardContentView(model: model, labels: labels)
            .task {
                await model.load()
            }
    }
}
