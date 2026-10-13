//
// SignalCreateRequestView.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Collects a feature request and displays its submission result.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalCreateRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.kickstartPremiumUser) private var isPremium
    @State private var model: SignalSubmissionModel
    @FocusState private var isTitleFocused: Bool

    let labels: SignalLabels

    /// Creates a submission form using the board client, content limits, and display labels.
    init(client: SignalClient, limits: SignalContentLimits, labels: SignalLabels) {
        _model = State(initialValue: SignalSubmissionModel(client: client, limits: limits))
        self.labels = labels
    }

    var body: some View {
        Form {
            if model.submitted {
                Text(labels.confirmationMessage)

                Button {
                    dismiss()
                } label: {
                    Label(String(localized: "Done", bundle: .module), systemImage: "checkmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Section {
                    VStack(alignment: .leading) {
                        TextField(text: $model.title, prompt: Text("Title", bundle: .module)) {
                            Text("Title", bundle: .module)
                        }
                        .focused($isTitleFocused)
                        .labelsHidden()

                        SignalCharacterCounter(text: model.title, limit: model.limits.title)
                    }
                }
                .disabled(model.isSubmitting)

                Section {
                    VStack(alignment: .leading) {
                        SignalMultilineField(
                            text: $model.description,
                            prompt: Text("Description", bundle: .module),
                            lineLimit: 5...12
                        )

                        SignalCharacterCounter(text: model.description, limit: model.limits.description)
                    }
                }
                .disabled(model.isSubmitting)

                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }

                Button {
                    Task { await model.submit(isPremium: isPremium) }
                } label: {
                    Label(String(localized: "Send", bundle: .module), systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .disabled(model.canSubmit == false)
                .buttonStyle(.plain)

                if model.isSubmitting {
                    ProgressView()
                }
            }
        }
        .dismissesKeyboardOnScroll()
        .navigationTitle(Text(labels.suggestionTitle))
        .inlineNavigationBar()
        .navigationBarBackButtonHidden(model.isSubmitting)
        .defaultFocus($isTitleFocused, true)
        .formStyle(.grouped)
    }
}
