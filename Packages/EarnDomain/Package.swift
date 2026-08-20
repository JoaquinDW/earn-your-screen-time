// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EarnDomain",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "EarnDomain", targets: ["EarnDomain"])
    ],
    targets: [
        .target(name: "EarnDomain"),
        .testTarget(name: "EarnDomainTests", dependencies: ["EarnDomain"])
    ]
)
