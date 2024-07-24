// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SabaDownloader",
    platforms: [
        .macOS(.v11), .tvOS(.v13), .iOS(.v13)
    ],
    products: [
        .library(
            name: "SabaDownloader",
            targets: ["SabaDownloader", "QueueDownloadManager"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SabaDownloader",
            dependencies: []),
        .target(
            name: "QueueDownloadManager",
            dependencies: [
                "SabaDownloader"
            ]),
        .testTarget(
            name: "SabaDownloaderTests",
            dependencies: ["SabaDownloader"]),
    ]
)
