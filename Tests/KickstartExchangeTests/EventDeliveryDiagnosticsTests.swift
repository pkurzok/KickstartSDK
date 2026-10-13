//
// EventDeliveryDiagnosticsTests.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import Foundation
import Testing
@testable import KickstartExchange

/// Verifies diagnostics produced by failed development event delivery.
@MainActor
@Suite("Development impression diagnostics")
struct EventDeliveryDiagnosticsTests {
    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("A development impression failure reports once")
    func developmentFailureReports() async throws {
        let handler = readyHandler(impression: .failure(URLError(.timedOut)))
        let recorder = DiagnosticRecorder()
        let appRunStore = ExchangeAdRunStore()
        let model = makeModel(handler: handler, recorder: recorder, appRunStore: appRunStore)
        await model.load()

        _ = try #require(await model.recordClick())
        try await waitForImpression(in: appRunStore)
        #expect(await handler.requests().count { $0.url == ExchangeEndpoint.impressions } == 3)
        #expect(recorder.messages == [Self.impressionDiagnostic])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("Shipping impression failures remain quiet")
    func shippingFailureStaysQuiet() async throws {
        let handler = readyHandler(
            impression: .success(TestFixtures.response(data: Data(), statusCode: 503))
        )
        let recorder = DiagnosticRecorder()
        let appRunStore = ExchangeAdRunStore()
        let model = makeModel(
            handler: handler,
            recorder: recorder,
            appRunStore: appRunStore,
            isDevelopment: false
        )
        await model.load()

        _ = try #require(await model.recordClick())
        try await waitForImpression(in: appRunStore, isDevelopment: false)
        #expect(await handler.requests().count { $0.url == ExchangeEndpoint.impressions } == 3)
        #expect(recorder.messages.isEmpty)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("Canceled impression delivery remains quiet")
    func cancellationStaysQuiet() async throws {
        let handler = readyHandler(impression: .failure(URLError(.cancelled)))
        let recorder = DiagnosticRecorder()
        let appRunStore = ExchangeAdRunStore()
        let model = makeModel(handler: handler, recorder: recorder, appRunStore: appRunStore)
        await model.load()

        _ = try #require(await model.recordClick())
        try await waitForImpression(in: appRunStore)
        #expect(await handler.requests().count { $0.url == ExchangeEndpoint.impressions } == 1)
        #expect(recorder.messages.isEmpty)
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    private func waitForImpression(in appRunStore: ExchangeAdRunStore, isDevelopment: Bool = true) async throws {
        let key = ExchangeAdRunKey(
            apiKey: TestFixtures.apiKey,
            bundleIdentifier: TestFixtures.bundleIdentifier,
            platform: .iOS,
            development: isDevelopment
        )
        try #require(appRunStore.hasStartedImpression(for: key))

        // Await the existing delivery task, including all retries and its final diagnostic decision.
        let task = try #require(appRunStore.beginImpression(for: key) {
            Issue.record("Expected to reuse the impression task started by the model.")
        })
        await task.value
    }

    private static let impressionDiagnostic =
        """
        Kickstart Exchange: The test ad impression could not be recorded. \
        Check the network connection and reload the test ad.
        """

    private func readyHandler(
        impression: Result<MockRequestHandler.Response, URLError>
    ) -> MockRequestHandler {
        MockRequestHandler([
            .success(TestFixtures.response(data: TestFixtures.sessionResponse())),
            .success(TestFixtures.response(data: TestFixtures.creativeResponse())),
            .success(TestFixtures.response(data: TestFixtures.validPNG)),
            impression,
            impression,
            impression
        ])
    }

    @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
    private func makeModel(
        handler: MockRequestHandler,
        recorder: DiagnosticRecorder,
        appRunStore: ExchangeAdRunStore,
        isDevelopment: Bool = true
    ) -> ExchangeAdViewModel {
        ExchangeAdViewModel(
            apiKey: TestFixtures.apiKey,
            bundleIdentifier: TestFixtures.bundleIdentifier,
            appVersion: TestFixtures.appVersion,
            buildVersion: TestFixtures.buildVersion,
            request: { request in
                if request.url?.absoluteString == TestFixtures.clickURL {
                    return TestFixtures.completedClickResponse
                }
                return try await handler.response(for: request)
            },
            isDevelopment: isDevelopment,
            impressionRetrySleep: { _ in },
            appRunStore: appRunStore,
            diagnosticHandler: recorder.record
        )
    }
}
