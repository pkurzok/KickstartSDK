//
// SignalRequestDetailView.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Displays a feature request, its discussion, and the interactions enabled by its configuration.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalRequestDetailView: View {
    @Environment(\.kickstartPremiumUser) private var isPremium
    @State private var model: SignalDetailModel
    @State private var comment = ""

    let translation: SignalTranslationModel
    let configuration: SignalConfiguration?
    let labels: SignalLabels

    /// Creates a detail screen that shares request state and translations with its board.
    init(
        model: SignalDetailModel, translation: SignalTranslationModel,
        configuration: SignalConfiguration?, labels: SignalLabels
    ) {
        _model = State(initialValue: model)
        self.translation = translation
        self.configuration = configuration
        self.labels = labels
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    if configuration?.interactionsEnabled != false {
                        SignalVoteButton(model: model)
                    } else {
                        Text(model.request.voteCount, format: .number)
                            .monospacedDigit()
                            .fixedSize()
                            .accessibilityLabel(Text("\(model.request.voteCount) votes", bundle: .module))
                    }

                    SignalRequestText(
                        request: model.request, translation: translation, descriptionLineLimit: nil
                    )
                }
            }

            SignalTranslationStatusView(model: translation)

            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            if let message = model.submissionMessage {
                Section {
                    Text(message)
                }
            }

            if configuration?.interactionsEnabled != false {
                if model.developerReplies.isEmpty == false {
                    Section {
                        ForEach(model.developerReplies) { comment in
                            SignalCommentRow(comment: comment, translation: translation)
                        }
                    } header: {
                        Text(labels.developerName)
                    }
                }

                if model.userComments.isEmpty == false || model.commentsError != nil || model.commentsCursor != nil {
                    Section {
                        ForEach(model.userComments) { comment in
                            SignalCommentRow(comment: comment, translation: translation)
                        }

                        if let error = model.commentsError {
                            Text(error).foregroundStyle(.red)

                            Button(String(localized: "Try again", bundle: .module), systemImage: "arrow.clockwise") {
                                Task { await model.load(cursor: model.commentsCursor) }
                            }
                            .disabled(model.isBusy)
                        }

                        if model.commentsCursor != nil && model.commentsError == nil {
                            Button(
                                String(localized: "Load more comments", bundle: .module),
                                systemImage: "arrow.down"
                            ) {
                                Task { await model.load(cursor: model.commentsCursor) }
                            }
                            .disabled(model.isBusy)
                        }
                    } header: {
                        if model.userComments.isEmpty == false {
                            Text("Comments", bundle: .module)
                        }
                    }
                }

                if let limits = configuration?.limits {
                    Section {
                        VStack(alignment: .leading) {
                            HStack {
                                SignalMultilineField(
                                    text: $comment,
                                    prompt: Text("Write your feedback here", bundle: .module),
                                    lineLimit: 3...8
                                )
                                .disabled(model.isBusy)

                                if model.isSubmittingComment {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityLabel(Text("Sending comment", bundle: .module))
                                }
                            }

                            SignalCharacterCounter(text: comment, limit: limits.comment)
                        }

                        Button {
                            Task {
                                if await model.submitComment(comment, limit: limits.comment, isPremium: isPremium) {
                                    comment = ""
                                }
                            }
                        } label: {
                            Label(String(localized: "Send", bundle: .module), systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .disabled(model.canSubmitComment(comment, limit: limits.comment) == false)
                        .buttonStyle(.plain)
                    } header: {
                        Text("Your Comment", bundle: .module)
                    }
                }
            }
        }
        .dismissesKeyboardOnScroll()
        .navigationTitle(Text(labels.detailTitle))
        .inlineNavigationBar()
        .formStyle(.grouped)
        .toolbar {
            #if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
            ToolbarItem {
                SignalTranslationButton(model: translation)
            }
            #endif
        }
        .signalTranslation(
            model: translation,
            texts: [model.request.title, model.request.description] + model.comments.map(\.body)
        )
        .task {
            await model.load(interactionsEnabled: configuration?.interactionsEnabled != false)
        }
    }
}
