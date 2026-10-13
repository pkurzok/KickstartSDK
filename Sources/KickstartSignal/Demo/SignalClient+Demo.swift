//
// SignalClient+Demo.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
extension SignalClient {
    /// An interactive, in-memory board using the normal client and view models.
    /// No network, StoreKit, or persistent identity storage is used. Submissions
    /// receive unpublished receipts; they do not change the public sample data.
    /// Share the returned client between boards to share their demo votes.
    ///
    /// - Parameters:
    ///   - requests: The published requests shown on the sample board.
    ///   - comments: Published comments grouped by request ID.
    /// - Returns: A new client with its own temporary votes and submission receipts.
    static func demo(
        requests: [SignalRequest],
        comments: [String: [SignalComment]] = [:]
    ) -> SignalClient {
        let transport = SignalDemoTransport(requests: requests, comments: comments)
        return SignalClient(
            apiKey: "ks_live_" + String(repeating: "d", count: 43),
            identities: SignalIdentityStore(defaults: nil),
            appTransaction: { throw SignalError.appVerification },
            bundleID: "tools.kickstart.signal.demo",
            transport: { try await transport.send($0) }
        )
    }
}
