// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpendOwlDemo-SwiftUI",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SpendOwlDemo-SwiftUI",
            dependencies: [
                .product(name: "SpendOwl", package: "spendowl-ios")
            ],
            path: "SpendOwlDemo-SwiftUI"
        )
    ]
)
