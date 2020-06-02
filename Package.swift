// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "UDPBroadcastConnection",
    products: [
        .library(name: "UDPBroadcastConnection", targets: ["UDPBroadcast"]),
        .library(name: "UDPBroadcastConnectionDynamic", type: .dynamic, targets: ["UDPBroadcast"])
    ],
    targets: [
        .target(name: "UDPBroadcast")
    ]
)
