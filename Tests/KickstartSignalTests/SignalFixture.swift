//
// SignalFixture.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartSignal

enum SignalFixture {
    static let apiKey = "ks_live_" + String(repeating: "a", count: 43)
    static let requestID = "ksreq_" + String(repeating: "a", count: 32)

    static func response(_ operation: String) throws -> (Data, Int) {
        let url = try #require(Bundle.module.url(forResource: "signal-v1-contract", withExtension: "json"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])

        let operations = try #require(fixture["operations"] as? [String: Any])
        let item = try #require(operations[operation] as? [String: Any])
        let success = try #require(item["success"] as? [String: Any])
        let status = try #require(success["status"] as? Int)

        return (try JSONSerialization.data(withJSONObject: #require(success["response"])), status)
    }

    static func request(
        votes: Int = 3,
        status: SignalStatus = .planned,
        id: String = requestID,
        creationOrder: UInt64 = 1
    ) -> SignalRequest {
        SignalRequest(
            id: id,
            creationOrder: creationOrder,
            title: "Folders",
            description: "Organize things",
            status: status,
            voteCount: votes,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    static func encoded<T: Encodable>(_ value: T) throws -> (Data, Int) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try encoder.encode(value), 200)
    }

    static func statusPages(
        _ requests: [SignalRequest],
        cursors: [SignalStatus: String] = [:]
    ) throws -> [String: (Data, Int)] {
        try Dictionary(
            uniqueKeysWithValues: SignalStatus.allCases.map { status in
                let page = SignalRequestPage(
                    requests: requests.filter { $0.status == status },
                    nextCursor: cursors[status]
                )
                return (status.rawValue, try encoded(page))
            }
        )
    }

    static func statusPage(for request: URLRequest, in pages: [String: (Data, Int)]) -> (Data, Int)? {
        guard request.httpMethod == "GET" else {
            return nil
        }

        guard let url = request.url, url.path == "/signal/v1/requests" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        guard let queryItems = components?.queryItems else {
            return nil
        }

        if queryItems.contains(where: { $0.name == "cursor" }) {
            return nil
        }

        guard let status = queryItems.first(where: { $0.name == "status" })?.value else {
            return nil
        }

        return pages[status]
    }

    static func body(_ request: URLRequest) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
    }
}
