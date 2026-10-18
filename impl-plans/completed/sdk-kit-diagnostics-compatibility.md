# Shared SDK diagnostics compatibility

Issue: https://github.com/tacogips/apple-gateway/issues/14

Apple gateway and Gmail gateway link the same GatewaySDKKit package. Gmail's
provider diagnostics fix requires the additive 0.1.1 API; Apple's exact 0.1.0
constraint otherwise prevents a consumer from resolving both gateways.

Update Apple gateway's exact dependency to the public 0.1.1 release and publish
Apple gateway 0.1.13. No Notes behavior or new metadata is introduced here.
Validate the complete Swift tests, smoke tests and SwiftLint; build and verify
both architecture archives, publish the release, and verify the Homebrew formula
and public API metadata. Riela will consume the immutable released revision.

Validation: public SDKKit0.1.1 at b133fcaab52265dcd508df7e2c3f11a073d20d83 resolves successfully. All288 tests, smoke tests and SwiftLint passed. Both architecture archive/publication gates follow.

Completed v0.1.13 at6a7df871e1ed76a5e374a35f4e4da9760e070535 with four public asset digests verified. Both architecture binaries/help/notifier/checksums passed. Tap57a63736 audit/fetch/upgrade/test passed; metadata workflow39123283125 succeeded, immutable d71843be677897942f20b9f9dbdf4ba54b067cf1 and public main version/formula hash verified.
