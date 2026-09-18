// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIQuotaBar",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AIQuotaBar", targets: ["AIQuotaBar"])
    ],
    targets: [
        .executableTarget(name: "AIQuotaBar"),
        .testTarget(
            name: "AIQuotaBarTests",
            dependencies: ["AIQuotaBar"]
        )
    ]
)
