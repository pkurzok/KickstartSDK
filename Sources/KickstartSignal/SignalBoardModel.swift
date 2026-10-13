//
// SignalBoardModel.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Observation

/// Loads a board by status and shares request updates and translation state with its detail views.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor @Observable
final class SignalBoardModel {
    static let statusChoices = SignalStatus.allCases.filter { $0 != .declined }

    let client: SignalClient
    let translation = SignalTranslationModel()
    var configuration: SignalConfiguration?
    var allRequests: [SignalRequest] = []
    var status: SignalStatus?
    var isLoading = false
    var error: String?
    var sectionCursors: [SignalStatus: String] = [:]

    private var hasLoaded = false
    private var failedSection: SignalStatus?

    @ObservationIgnored private var detailModels: [String: SignalDetailModel] = [:]

    /// Loaded requests matching the selected status, ordered by votes.
    var requests: [SignalRequest] {
        let matching = allRequests.filter { request in
            status == nil || request.status == status
        }

        return matching.sorted(by: SignalRequest.mostVotedFirst)
    }

    /// The next page cursor for the selected status, or `nil` when viewing all statuses.
    var nextCursor: String? {
        guard let status else { return nil }
        return sectionCursors[status]
    }

    /// Nonempty groups of visible requests in the board's status order.
    var sections: [SignalBoardSection] {
        let visibleRequests = requests
        return SignalStatus.allCases.compactMap { status in
            let matching = visibleRequests.filter { $0.status == status }
            guard matching.isEmpty == false else { return nil }
            return SignalBoardSection(status: status, requests: matching)
        }
    }

    /// Creates a board that loads its settings and requests on demand.
    init(client: SignalClient, status: SignalStatus? = nil) {
        self.client = client
        self.status = status
    }

    /// Returns a cached detail model whose successful request changes update this board.
    func detailModel(for request: SignalRequest) -> SignalDetailModel {
        if let model = detailModels[request.id] { return model }
        let current = allRequests.first { $0.id == request.id } ?? request

        let model = SignalDetailModel(request: current, client: client) { [weak self] updated in
            self?.update(updated)
        }

        detailModels[request.id] = model
        return model
    }

    /// Replaces an already loaded request with the result of a detail action.
    private func update(_ request: SignalRequest) {
        guard let index = allRequests.firstIndex(where: { $0.id == request.id }) else { return }
        allRequests[index] = request
    }

    /// Reconciles cached detail models with the current board requests.
    private func refreshDetailModels() {
        for request in allRequests {
            detailModels[request.id]?.refresh(request)
        }
    }

    /// Adds new request identifiers without overwriting requests already updated locally.
    private func append(_ incoming: [SignalRequest]) {
        // Keep locally updated requests when an older page includes them again.
        var existing = Set(allRequests.map(\.id))

        allRequests += incoming.filter {
            existing.insert($0.id).inserted
        }

        refreshDetailModels()
    }

    /// Loads configuration and the first page of every status once.
    /// Publishes request pages only when every status succeeds; failures remain available for retry.
    /// Once started, the read finishes for this model even if the calling view disappears.
    func load() async {
        guard Task.isCancelled == false, hasLoaded == false, isLoading == false else { return }

        isLoading = true
        error = nil

        defer { isLoading = false }

        await Task {
            await loadInitialPages()
        }.value
    }

    /// Fetches the configuration and status pages, retaining failures for the board's retry action.
    private func loadInitialPages() async {
        do {
            if configuration == nil {
                configuration = try await client.loadConfiguration()
            }

            let pages = try await loadStatusPages(client: client)
            try Task.checkCancellation()

            let incoming = Dictionary(
                pages.values.flatMap(\.requests).map { ($0.id, $0) },
                uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 }
            )

            append(Array(incoming.values))
            sectionCursors = pages.compactMapValues(\.nextCursor)
            hasLoaded = true
        } catch is CancellationError {
            // ignore
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Fetches status pages concurrently and fails the whole batch if any page fails.
    private func loadStatusPages(client: SignalClient) async throws -> [SignalStatus: SignalRequestPage] {
        try await withThrowingTaskGroup(of: (SignalStatus, SignalRequestPage).self) { group in
            for status in SignalStatus.allCases {
                group.addTask {
                    let page = try await client.listRequests(status: status, limit: 100)
                    return (status, page)
                }
            }

            var pages: [SignalStatus: SignalRequestPage] = [:]

            for try await (status, page) in group {
                pages[status] = page
            }

            return pages
        }
    }

    /// Appends the next page for one status, retaining its cursor if the request fails.
    func loadMore(in section: SignalStatus) async {
        guard hasLoaded, isLoading == false, let cursor = sectionCursors[section] else { return }
        isLoading = true
        defer { isLoading = false }

        error = nil
        failedSection = nil

        do {
            let page = try await client.listRequests(status: section, cursor: cursor, limit: 100)
            try Task.checkCancellation()
            append(page.requests)
            sectionCursors[section] = page.nextCursor
        } catch is CancellationError {
            // ignore
        } catch {
            failedSection = section
            self.error = error.localizedDescription
        }
    }

    /// Retries the failed status page, or the initial board load if it has not succeeded.
    func retry() async {
        if let failedSection {
            await loadMore(in: failedSection)
        } else {
            await load()
        }
    }
}
