import Foundation
import AppleGatewayCore

let exitCode = AppleGatewayCommandLine.run(
  role: .full,
  arguments: CommandLine.arguments,
  environment: ProcessInfo.processInfo.environment
)
exit(exitCode)
