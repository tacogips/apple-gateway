// swift-tools-version: 6.0

import PackageDescription

let appleGatewayInfoPlistLinkerSettings: [LinkerSetting] = [
  .unsafeFlags([
    "-Xlinker", "-sectcreate",
    "-Xlinker", "__TEXT",
    "-Xlinker", "__info_plist",
    "-Xlinker", "Resources/AppleGatewayInfo.plist"
  ])
]

let package = Package(
  name: "apple-gateway",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AppleGatewayCore", targets: ["AppleGatewayCore"]),
    .executable(name: "apple-gateway", targets: ["AppleGatewayCLI"]),
    .executable(name: "apple-gateway-reader", targets: ["AppleGatewayReaderCLI"]),
    .executable(name: "AppleGatewayNotifier", targets: ["AppleGatewayNotifier"]),
    .executable(name: "AppleGatewaySmokeTests", targets: ["AppleGatewaySmokeTests"])
  ],
  dependencies: [
    // The operator switches this path dependency to a URL pin when the kit is published.
    .package(path: "../../gateway-sdk-kit")
  ],
  targets: [
    .target(
      name: "AppleGatewayCore",
      dependencies: [.product(name: "GatewaySDKKit", package: "gateway-sdk-kit")]
    ),
    .executableTarget(
      name: "AppleGatewayCLI",
      dependencies: ["AppleGatewayCore"],
      linkerSettings: appleGatewayInfoPlistLinkerSettings
    ),
    .executableTarget(
      name: "AppleGatewayReaderCLI",
      dependencies: ["AppleGatewayCore"],
      linkerSettings: appleGatewayInfoPlistLinkerSettings
    ),
    .executableTarget(
      name: "AppleGatewayNotifier",
      dependencies: ["AppleGatewayCore"]
    ),
    .testTarget(
      name: "AppleGatewayCoreTests",
      dependencies: ["AppleGatewayCore"]
    ),
    .executableTarget(
      name: "AppleGatewaySmokeTests",
      dependencies: ["AppleGatewayCore"],
      path: "Tests/AppleGatewaySmokeTests"
    )
  ],
  swiftLanguageModes: [.v6]
)
