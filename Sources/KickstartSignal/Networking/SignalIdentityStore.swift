//
// SignalIdentityStore.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation

/// Signal state belongs to this app installation, independent of its API key.
@MainActor
final class SignalIdentityStore {
    private let defaults: UserDefaults?
    private let votesKey = "tools.kickstart.signal.votes"
    private var memoryIdentity: String?
    private var memoryVotes: Set<String> = []

    /// Creates a store backed by user defaults, or kept entirely in memory when `defaults` is `nil`.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// Returns the installation's anonymous UUID, creating one if it is missing or invalid.
    func identity() -> String {
        guard let defaults else {
            if let memoryIdentity {
                return memoryIdentity
            }

            let identity = UUID().uuidString.lowercased()
            memoryIdentity = identity
            return identity
        }

        let key = "tools.kickstart.signal.identity"

        if let stored = defaults.string(forKey: key), UUID(uuidString: stored) != nil {
            return stored
        }

        let identity = UUID().uuidString.lowercased()
        defaults.set(identity, forKey: key)
        return identity
    }

    /// Reads locally recorded votes without consulting the server.
    func votedIDs() -> Set<String> {
        guard let defaults else { return memoryVotes }
        return Set(defaults.stringArray(forKey: votesKey) ?? [])
    }

    /// Updates the local vote record after the server confirms a vote or its removal.
    func setVote(_ voted: Bool, requestID: String) {
        var ids = votedIDs()

        if voted {
            ids.insert(requestID)
        } else {
            ids.remove(requestID)
        }

        if let defaults {
            defaults.set(ids.sorted(), forKey: votesKey)
        } else {
            memoryVotes = ids
        }
    }
}
