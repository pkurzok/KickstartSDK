//
// SignalSuspendedTransport.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// Suspends one response without timing assumptions, including transports that
/// finish after cancellation. Tests explicitly release it before returning.
actor SignalSuspendedTransport {
    private var responses: [(Data, Int)]
    private let statusPages: [String: (Data, Int)]
    private let blockedIndex: Int
    private var requests: [URLRequest] = []
    private var blocked = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Void, Never>?

    init(responses: [(Data, Int)], blockedIndex: Int, statusPages: [String: (Data, Int)] = [:]) {
        self.responses = responses
        self.blockedIndex = blockedIndex
        self.statusPages = statusPages
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count
        requests.append(request)
        let response: (Data, Int)

        if let page = SignalFixture.statusPage(for: request, in: statusPages) {
            response = page
        } else {
            guard responses.isEmpty == false else { throw URLError(.badServerResponse) }
            response = responses.removeFirst()
        }

        if index == blockedIndex {
            await withCheckedContinuation { continuation in
                responseWaiter = continuation
                blocked = true
                waiter?.resume()
                waiter = nil
            }
        }

        return response
    }

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func recorded() -> [URLRequest] {
        requests
    }

    func release() {
        responseWaiter?.resume()
        responseWaiter = nil
    }
}
