//
// SignalTranslationGate.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

@MainActor
final class SignalTranslationGate {
    private let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<String, Never>?

    func translate(_ text: String) async -> String {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(())
        }
    }

    func waitUntilStarted() async {
        for await _ in started.stream { return }
    }

    func complete(_ text: String) {
        continuation?.resume(returning: text)
        continuation = nil
    }
}
