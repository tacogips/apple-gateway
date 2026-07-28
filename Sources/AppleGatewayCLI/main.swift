import Foundation
import AppleGatewayCore

if CommandLine.arguments.dropFirst().first == "__phone-audio-player" {
  exit(PhoneAudioPlayerCommand.run(arguments: Array(CommandLine.arguments.dropFirst(2))))
}

if CommandLine.arguments.dropFirst().first == "__phone-audio-listener" {
  exit(PhoneAudioListenerCommand.run(arguments: Array(CommandLine.arguments.dropFirst(2))))
}

let exitCode = AppleGatewayCommandLine.run(
  role: .full,
  arguments: CommandLine.arguments,
  environment: ProcessInfo.processInfo.environment
)
exit(exitCode)
