//
// SignalTransportRecorder.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

actor SignalTransportRecorder {
    private var requests: [URLRequest] = []
    private var responses: [(Data, Int)]
    private let statusPages: [String: (Data, Int)]
    init(responses: [(Data, Int)], statusPages: [String: (Data, Int)] = [:]) {
        self.responses = responses
        self.statusPages = statusPages
    }
    func send(_ request: URLRequest) throws -> (Data, Int) {
        requests.append(request)

        if let page = SignalFixture.statusPage(for: request, in: statusPages) {
            return page
        }

        guard responses.isEmpty == false else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }

    func enqueue(_ response: (Data, Int)) {
        responses.append(response)
    }

    func recorded() -> [URLRequest] {
        requests
    }
}
