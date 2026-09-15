// swift-tools-version: 6.0

import PackageDescription



let package = Package(
    name: "MonetizationTools",
    
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    
    products: [
        .library(
            name: "MonetizationTools",
            targets: ["MonetizationTools"]),
    ],
    
    dependencies: [
        .package(url: "https://github.com/RougeWare/Swift-Special-String.git", from: "1.2.0"),
    ],
    
    targets: [
        .target(
            name: "MonetizationTools",
            dependencies: [
                .product(name: "SpecialString", package: "Swift-Special-String"),
            ]),
        
        .testTarget(
            name: "MonetizationToolsTests",
            dependencies: ["MonetizationTools"]),
    ]
)
