// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

//
//  Package.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import PackageDescription

let package = Package(
    name: "SpendOwl",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SpendOwl",
            targets: ["SpendOwl"]
        )
    ],
    targets: [
        .target(
            name: "SpendOwl",
            dependencies: [],
            path: "Sources/SpendOwl",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "SpendOwlTests",
            dependencies: ["SpendOwl"],
            path: "Tests/SpendOwlTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
