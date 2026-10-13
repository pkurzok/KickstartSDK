//
// SignalRedirectDelegate.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// An app key must never follow a redirect to another origin.
final class SignalRedirectDelegate: NSObject, URLSessionTaskDelegate {
    /// Rejects every redirect so API credentials cannot be forwarded to a new destination.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
