// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "vmcli",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "vmcli",
      targets: ["vmcli"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
  ],
  targets: [
    .executableTarget(
      name: "vmcli",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources"
    )
  ]
)
