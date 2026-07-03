# Homebrew Packaging

apple-gateway is a macOS CLI and GraphQL bridge for Apple apps. This project
ships two Homebrew release paths:

- Formula: unsigned tarballs containing `bin/apple-gateway`,
  `bin/apple-gateway-reader`, `libexec/AppleGatewayNotifier.app`, and
  `share/apple-gateway/shortcuts`.
- Cask: signed, notarized, and stapled macOS DMGs containing both command line
  tools, `AppleGatewayNotifier.app`, and the Clock alarm Shortcuts bridge
  package.

Swift formula archives are macOS-only by default. Add Linux archives only after
the project has a reviewed Swift Linux build and runtime contract.

## Formula

Build release archives:

```bash
scripts/build-homebrew-release.sh darwin-arm64 darwin-x64
```

Release builds validate that every Clock alarm bridge shortcut declared by
`packaging/shortcuts/manifest.json` has a real exported `.shortcut` file in
`packaging/shortcuts/`. The validation fails before archive or DMG staging if
exports are missing, so release assets cannot silently ship only `README.md`,
`SOURCE.md`, and `manifest.json` as the shortcut package.
Both release builders force validation against the repo `packaging/shortcuts/`
directory that they stage, so an `APPLE_GATEWAY_SHORTCUTS_DIR` override cannot
make release packaging pass against a different temporary shortcuts directory.

For incomplete local/manual checks only, use the documented bypass:

```bash
APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1 \
  scripts/build-homebrew-release.sh --validate-shortcuts-only
```

Do not use that bypass for production release packaging.

The command writes archives and checksums under `dist/homebrew/`:

```text
dist/homebrew/apple-gateway-<version>-darwin-arm64.tar.gz
dist/homebrew/apple-gateway-<version>-darwin-arm64.tar.gz.sha256
dist/homebrew/apple-gateway-<version>-darwin-x64.tar.gz
dist/homebrew/apple-gateway-<version>-darwin-x64.tar.gz.sha256
```

Publish those assets to the
`https://github.com/tacogips/apple-gateway/releases/tag/v<version>` GitHub
release, then render the formula into a tap checkout:

```bash
scripts/render-homebrew-formula.sh <version> ../homebrew-tap/Formula/apple-gateway.rb
```

## Cask

Build signed and notarized DMGs on macOS:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  scripts/build-homebrew-cask-release.sh darwin-arm64 darwin-x64
```

This writes:

```text
dist/homebrew-cask/apple-gateway-<version>-darwin-arm64.dmg
dist/homebrew-cask/apple-gateway-<version>-darwin-arm64.dmg.sha256
dist/homebrew-cask/apple-gateway-<version>-darwin-x64.dmg
dist/homebrew-cask/apple-gateway-<version>-darwin-x64.dmg.sha256
```

Render the Cask:

```bash
scripts/render-homebrew-cask.sh <version> ../homebrew-tap/Casks/apple-gateway.rb
```

For a tagged release, the local wrapper verifies the tag, builds DMGs, uploads
release assets to `tacogips/apple-gateway` by default, and renders the tap
Cask:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  scripts/release-homebrew-cask-local.sh v<version>
```

## Verification

From the tap checkout:

```bash
ruby -c Formula/apple-gateway.rb
brew audit --strict apple-gateway || brew audit --strict --formula apple-gateway
brew fetch --cask tacogips/tap/apple-gateway
HOMEBREW_NO_GITHUB_API=1 brew audit --cask tacogips/tap/apple-gateway
```

If online audit fails due local GitHub credentials or rate limits, run the
non-online audit and record the limitation.
