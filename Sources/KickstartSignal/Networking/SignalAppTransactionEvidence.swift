//
// SignalAppTransactionEvidence.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import StoreKit
import OSLog

/// Supplies signed StoreKit evidence when Signal requires verification of the installed app.
@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
enum SignalAppTransactionEvidence {
    /// Returns the locally verified app transaction's signed JWS representation.
    /// Cancellation is preserved; other failures become `SignalError.appVerification`.
    static func current() async throws -> String {
        do {
            let result = try await AppTransaction.shared

            guard case .verified = result else {
                throw SignalError.appVerification
            }
            let evidence = result.jwsRepresentation

            guard evidence.isEmpty == false else {
                throw SignalError.appVerification
            }

            return evidence
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            Logger(subsystem: "tools.kickstart.signal", category: "Verification")
                .debug("Signal could not verify this app. Use a valid App Store or TestFlight build.")
            #endif
            throw SignalError.appVerification
        }
    }
}
