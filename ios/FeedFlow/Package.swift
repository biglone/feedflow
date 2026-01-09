// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeedFlow",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FeedFlow",
            targets: ["FeedFlow"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2"),
    ],
    targets: [
        .target(
            name: "FeedFlow",
            dependencies: ["FeedKit"],
            path: "."
        ),
    ]
)
