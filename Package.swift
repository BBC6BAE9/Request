// swift-tools-version: 5.10.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Request",
    platforms: [.macOS(.v10_13),
                .iOS(.v12),
                .tvOS(.v14),
                .watchOS(.v4),
                .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Request",
            targets: ["Request"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.9.1")),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.2"),
    ],
    targets: [
        .target(
            name: "Request",
            dependencies: ["Alamofire", .product(name: "SwiftProtobuf", package: "swift-protobuf"), "SwiftyJSON"]),
        .testTarget(
            name: "RequestTests",
            dependencies: ["Request"]),
    ]
)
