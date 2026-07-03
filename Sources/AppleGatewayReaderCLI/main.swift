import Foundation
import AppleGatewayCore

let exitCode = AppleGatewayCommandLine.run(
  role: .reader,
  arguments: CommandLine.arguments,
  environment: ProcessInfo.processInfo.environment
)
exit(exitCode)
