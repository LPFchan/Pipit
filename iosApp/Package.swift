// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PipitIOS",
    platforms: [ .iOS(.v16) ],
    products: [
        .library(name: "PipitIOS", targets: ["PipitApp"])
    ],
    targets: [
        .target(
            name: "PipitApp",
            path: "iosApp/",
            resources: [ .process("Resources") ]
        )
    ]
)
