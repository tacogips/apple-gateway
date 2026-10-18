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
    .package(url: "https://github.com/tacogips/gateway-sdk-kit.git", exact: "0.1.1")
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
