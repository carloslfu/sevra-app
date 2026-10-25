// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Sevra", platforms: [.macOS(.v14)],
  products: [
    .library(name: "SevraCore", targets: ["SevraCore"]),
    .executable(name: "SevraDesktop", targets: ["SevraApp"]),
    .executable(name: "sevra", targets: ["SevraCLI"]),
    .executable(name: "sevra-checks", targets: ["SevraChecks"]),
    .executable(name: "sevra-benchmark", targets: ["SevraBenchmark"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/carloslfu/slotstream.git",
      revision: "7578fb21e57ec362d19f5050922e0f583914935d"),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
  ],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .target(
      name: "SevraCore", dependencies: ["CSQLite", "ZIPFoundation"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .target(
      name: "SevraAI",
      dependencies: ["SevraCore", .product(name: "Slotstream", package: "slotstream")],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraApp", dependencies: ["SevraCore", "SevraAI"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraCLI", dependencies: ["SevraCore", "SevraAI"],
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraBenchmark", dependencies: ["SevraCore"], path: "Benchmarks",
      swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(
      name: "SevraChecks", dependencies: ["SevraCore"], path: "Tests",
      swiftSettings: [.swiftLanguageMode(.v5)]),
  ])
