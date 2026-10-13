//
// SignalVoteButton.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// The same vote control is used in the board and request details.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalVoteButton: View {
    @Environment(\.kickstartPremiumUser) private var isPremium
    @State private var showsError = false
    @State private var voteError: String?
    let model: SignalDetailModel

    var body: some View {
        Button {
            Task {
                voteError = await model.toggleVote(isPremium: isPremium)
                showsError = voteError != nil
            }
        } label: {
            VStack(spacing: 2) {
                Label(
                    model.hasVoted ? String(localized: "Remove vote", bundle: .module)
                        : String(localized: "Vote for this", bundle: .module),
                    systemImage: "arrowtriangle.up.fill"
                )
                .labelStyle(.iconOnly)
                .scaleEffect(x: 1, y: 0.5)

                Text(model.request.voteCount, format: .number)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(model.hasVoted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 48)
            .frame(minHeight: 44)
            .background(
                model.hasVoted ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(model.hasVoted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityHint(model.request.title)
        .accessibilityValue(Text("\(model.request.voteCount) votes", bundle: .module))
        .accessibilityAddTraits(model.hasVoted ? .isSelected : [])
        .alert(String(localized: "Unable to update vote", bundle: .module), isPresented: $showsError) {
        } message: {
            Text(voteError ?? "")
        }
    }
}
