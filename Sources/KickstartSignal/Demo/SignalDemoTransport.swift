//
// SignalDemoTransport.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// A local response source for the interactive demo, never a network fallback.
/// Votes update the sample requests in memory. Submissions receive unpublished receipts
/// without being added to the published requests or comments.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
actor SignalDemoTransport {
    private var requests: [SignalRequest]
    private let comments: [String: [SignalComment]]
    private let configuration: SignalConfiguration
    private var votes: Set<String> = []
    private var receipts: [String: SignalSubmission] = [:]

    /// Starts a demo session with the supplied requests, sorting each comment thread oldest first.
    init(requests: [SignalRequest], comments: [String: [SignalComment]]) {
        self.requests = requests
        self.comments = comments.mapValues { $0.sorted { $0.createdAt < $1.createdAt } }

        configuration = SignalConfiguration(
            interactionsEnabled: true,
            limits: .standard
        )
    }

    /// Handles a supported Signal route locally and returns its encoded response and HTTP status.
    /// Checks task cancellation before processing the request.
    func send(_ request: URLRequest) throws -> (Data, Int) {
        try Task.checkCancellation()

        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (Data(), 400)
        }

        let route = Array(url.pathComponents.dropFirst(3))
        let query = components.queryItems ?? []
        let method = request.httpMethod ?? "GET"

        switch (route, method) {
        case (["sessions"], "POST"):
            let session = "{\"session_token\":\"kss_\(String(repeating: "d", count: 43))\",\"expires_in\":900}"
            return (Data(session.utf8), 200)
        case (["config"], "GET"):
            return try response(configuration)
        case (["requests"], "GET"):
            return try requestPage(query: query)
        case (["requests"], "POST"):
            return try submit(request, isComment: false)
        default:
            break
        }

        guard route.count >= 2, route[0] == "requests",
              let index = requests.firstIndex(where: { $0.id == route[1] }) else {
            return (Data(), 404)
        }

        if route.count == 3, route[2] == "votes", method == "POST" || method == "DELETE" {
            return try vote(index: index, adding: method == "POST")
        }

        if route.count == 3, route[2] == "comments" {
            if method == "GET" {
                let page = page(comments[route[1]] ?? [], query: query, maximum: 100)
                return try response(SignalCommentPage(comments: page.items, nextCursor: page.cursor))
            }
            if method == "POST" { return try submit(request, isComment: true) }
        }

        return (Data(), 404)
    }

    /// Filters and sorts the sample requests before applying cursor pagination.
    private func requestPage(query: [URLQueryItem]) throws -> (Data, Int) {
        let status = query.first { $0.name == "status" }?.value
        let filtered = requests.filter { status == nil || $0.status.rawValue == status }
        let sorted = filtered.sorted(by: SignalRequest.mostVotedFirst)
        let page = page(sorted, query: query, maximum: 100)

        return try response(SignalRequestPage(requests: page.items, nextCursor: page.cursor))
    }

    /// Returns items after the cursor ID, with the requested limit clamped to `1...maximum`.
    /// An absent or unknown cursor starts from the beginning. Returns a next cursor only if more items remain.
    private func page<Item: Identifiable>(
        _ items: [Item], query: [URLQueryItem], maximum: Int
    ) -> (items: [Item], cursor: String?) where Item.ID == String {
        // Continue after the previous page's last item. Missing or unknown cursors start at the beginning.
        let cursor = query.first { $0.name == "cursor" }?.value

        var startIndex = 0

        if let cursor, let index = items.firstIndex(where: { $0.id == cursor }) {
            startIndex = index + 1
        }

        // Missing or invalid limits use the maximum; numeric limits stay within 1...maximum.
        let limitValue = query.first { $0.name == "limit" }?.value
        let requestedLimit = limitValue.flatMap(Int.init) ?? maximum
        let pageSize = max(1, min(requestedLimit, maximum))
        let endIndex = min(items.count, startIndex + pageSize)

        let pageItems = Array(items[startIndex..<endIndex])

        // A nil cursor tells the caller it has reached the final page.
        let hasMoreItems = endIndex < items.count
        let nextCursor = hasMoreItems ? pageItems.last?.id : nil

        return (pageItems, nextCursor)
    }

    /// Updates a request only when the demo vote changes, making repeated adds or removals idempotent.
    private func vote(index: Int, adding: Bool) throws -> (Data, Int) {
        let original = requests[index]
        let changed = adding ? votes.insert(original.id).inserted : votes.remove(original.id) != nil

        if changed {
            requests[index] = SignalRequest(
                id: original.id, creationOrder: original.creationOrder, title: original.title,
                description: original.description, status: original.status,
                voteCount: max(0, original.voteCount + (adding ? 1 : -1)),
                updatedAt: .now
            )
        }

        return try response(requests[index])
    }

    /// Validates a submission and returns a receipt without changing public sample data.
    /// Reuses receipts for the same route and idempotency key; new requests report the author
    /// as having voted, while comment receipts omit vote state.
    private func submit(_ request: URLRequest, isComment: Bool) throws -> (Data, Int) {
        guard let data = request.httpBody,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (Data(), 422)
        }

        // Both submission types require text, but comments and request titles have different limits.
        let text = body[isComment ? "body" : "title"] as? String ?? ""
        let description = body["description"] as? String ?? ""
        let limit = isComment ? configuration.limits.comment : configuration.limits.title

        // Match the submission forms' length validation by counting Unicode scalars.
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              text.unicodeScalars.count <= limit,
              description.unicodeScalars.count <= configuration.limits.description else {
            return (Data(), 422)
        }

        // Keep retry receipts separate for each submission route. Without a key, each call is a new submission.
        let key = (request.url?.path ?? "")
            + (request.value(forHTTPHeaderField: "Idempotency-Key") ?? UUID().uuidString)

        // Retrying the same submission returns its original receipt without creating another ID.
        if let receipt = receipts[key] { return try response(receipt) }

        let prefix = isComment ? "kscom_" : "ksreq_"

        // Return a receipt without adding anything to the public sample requests or comments.
        // Request receipts report the author's initial vote; comment receipts omit vote state.
        let receipt = SignalSubmission(
            id: prefix + UUID().uuidString.replacing("-", with: "").lowercased(),
            hasVoted: isComment ? nil : true
        )

        receipts[key] = receipt
        return try response(receipt, status: 201)
    }

    /// Encodes a demo response using the API's snake-case keys and ISO 8601 dates.
    private func response<Value: Encodable>(_ value: Value, status: Int = 200) throws -> (Data, Int) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try encoder.encode(value), status)
    }
}
