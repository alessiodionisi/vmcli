// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "vmcli",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "vmcli",
      targets: ["vmcli"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.2"),
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
