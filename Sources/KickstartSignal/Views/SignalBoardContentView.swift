//
// SignalBoardContentView.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import SwiftUI

/// Board content that participates in the host app's navigation stack.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct SignalBoardContentView: View {
    @Bindable var model: SignalBoardModel

    /// Tracks navigation because macOS may not call `onDisappear` when a destination covers the form.
    @State private var isShowingDestination = false

    let labels: SignalLabels

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.status) {
                    Text("All", bundle: .module).tag(nil as SignalStatus?)
                    #if !os(watchOS)
                    Divider()
                    #endif
                    ForEach(SignalBoardModel.statusChoices) { status in
                        Text(status.localizedTitle).tag(Optional(status))
                    }
                } label: { Text("Status", bundle: .module) }
            }

            SignalTranslationStatusView(model: model.translation)

            if let error = model.error {
                Section {
                    Text(error)

                    Button(String(localized: "Try again", bundle: .module), systemImage: "arrow.clockwise") {
                        Task { await model.retry() }
                    }
                }
            }

            if model.isLoading && model.allRequests.isEmpty {
                ProgressView(String(localized: "Loading…", bundle: .module))
                    .frame(maxWidth: .infinity)
            } else if model.requests.isEmpty && model.error == nil {
                Text(labels.emptyStatusMessage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }

            if model.status == nil {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.requests) { request in
                            SignalRequestRow(
                                model: model.detailModel(for: request), translation: model.translation,
                                allowsVoting: model.configuration?.interactionsEnabled != false
                            )
                        }

                        if model.sectionCursors[section.status] != nil {
                            Button(String(localized: "Load more", bundle: .module), systemImage: "arrow.down") {
                                Task { await model.loadMore(in: section.status) }
                            }
                            .disabled(model.isLoading)
                        }
                    } header: {
                        Text(section.status.localizedTitle)
                    }
                }
            } else {
                ForEach(model.requests) { request in
                    SignalRequestRow(
                        model: model.detailModel(for: request), translation: model.translation,
                        allowsVoting: model.configuration?.interactionsEnabled != false
                    )
                }
            }

            if let status = model.status, model.nextCursor != nil {
                Button(String(localized: "Load more", bundle: .module), systemImage: "arrow.down") {
                    Task { await model.loadMore(in: status) }
                }
                .disabled(model.isLoading)
            }
        }
        .navigationTitle(Text(labels.title))
        .navigationDestination(for: SignalRequest.self) { request in
            SignalRequestDetailView(
                model: model.detailModel(for: request), translation: model.translation,
                configuration: model.configuration, labels: labels
            )
            .onAppear { isShowingDestination = true }
            .onDisappear { isShowingDestination = false }
        }
        .navigationDestination(for: SignalBoardDestination.self) { _ in
            if let configuration = model.configuration {
                SignalCreateRequestView(client: model.client, limits: configuration.limits, labels: labels)
                    .onAppear { isShowingDestination = true }
                    .onDisappear { isShowingDestination = false }
            }
        }
        .formStyle(.grouped)
        .signalTranslation(
            model: model.translation, texts: model.allRequests.flatMap { [$0.title, $0.description] },
            isActive: isShowingDestination == false
        )
        .toolbar {
            #if canImport(Translation) && (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
            ToolbarItem {
                SignalTranslationButton(model: model.translation)
            }
            #endif
            if model.configuration != nil {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: SignalBoardDestination.createRequest) {
                        Label {
                            Text(labels.suggestionTitle)
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
    }
}
