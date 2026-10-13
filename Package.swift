// swift-tools-version: 6.2

//
// Package.swift
// KickstartSDK
// https://github.com/twostraws/KickstartSDK
// See LICENSE for license information.
//

import PackageDescription

let package = Package(
    name: "KickstartSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "KickstartSignal",
            targets: ["KickstartSignal"]
        ),
        .library(
            name: "KickstartExchange",
            targets: ["KickstartExchange"]
        )
    ],
    targets: [
        .target(name: "KickstartShared"),
        .target(
            name: "KickstartSignal",
            dependencies: ["KickstartShared"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KickstartSignalTests",
            dependencies: ["KickstartSignal"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .target(
            name: "KickstartExchange",
            dependencies: ["KickstartShared"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KickstartExchangeTests",
            dependencies: ["KickstartExchange"],
            resources: [
                .process("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
