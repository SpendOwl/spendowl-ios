// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpendOwlDemo-UIKit",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SpendOwlDemo-UIKit",
            dependencies: [
                .product(name: "SpendOwl", package: "spendowl-ios")
            ],
            path: "SpendOwlDemo-UIKit"
        )
    ]
)
