#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
artifact_name="apple-gateway"
product="apple-gateway"
reader_product="apple-gateway-reader"
notifier_app="AppleGatewayNotifier.app"
github_repository="tacogips/apple-gateway"
project_description="macOS CLI and GraphQL bridge for Apple apps"

usage() {
  cat <<EOF
Usage:
  scripts/render-homebrew-cask.sh <version> [output-file]

Reads archive checksums from:
  dist/homebrew-cask/$artifact_name-<version>-<target>.dmg.sha256

Environment:
  CASK_RELEASE_DIR       Directory containing archives and .sha256 files.
  CASK_RELEASE_BASE_URL  Release URL base. Defaults to GitHub v<version>.
  CASK_VERIFIED_URL      Verified URL prefix. Defaults from GitHub release URL.

Example:
  scripts/build-homebrew-cask-release.sh darwin-arm64 darwin-x64
  scripts/render-homebrew-cask.sh 0.1.0 ../homebrew-tap/Casks/$artifact_name.rb

This renderer expects signed, notarized, and stapled macOS .dmg artifacts.
EOF
}

sha_for_target() {
  local version target release_dir sha_file
  version="$1"
  target="$2"
  release_dir="$3"
  sha_file="$release_dir/$artifact_name-$version-$target.dmg.sha256"

  if [[ ! -f "$sha_file" ]]; then
    printf 'missing checksum file: %s\n' "$sha_file" >&2
    return 1
  fi

  awk '{print $1}' "$sha_file"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return
  fi
  if [[ "${1:-}" == "" ]]; then
    usage
    return 2
  fi

  local version output release_dir release_base_url default_verified_url verified_url
  version="$1"
  output="${2:-$repo_root/Casks/$artifact_name.rb}"
  release_dir="${CASK_RELEASE_DIR:-$repo_root/dist/homebrew-cask}"
  release_base_url="${CASK_RELEASE_BASE_URL:-https://github.com/$github_repository/releases/download/v$version}"
  default_verified_url="github.com/$github_repository/releases/download/"
  if [[ "$release_base_url" =~ ^https://github\.com/([^/]+/[^/]+)/releases/download/ ]]; then
    default_verified_url="github.com/${BASH_REMATCH[1]}/releases/download/"
  fi
  verified_url="${CASK_VERIFIED_URL:-$default_verified_url}"

  local darwin_arm64_sha darwin_x64_sha
  darwin_arm64_sha="$(sha_for_target "$version" darwin-arm64 "$release_dir")"
  darwin_x64_sha="$(sha_for_target "$version" darwin-x64 "$release_dir")"

  mkdir -p "$(dirname "$output")"
  cat > "$output" <<EOF
cask "apple-gateway" do
  version "$version"
  arch arm: "darwin-arm64", intel: "darwin-x64"

  sha256 arm: "$darwin_arm64_sha",
         intel: "$darwin_x64_sha"

  url "$release_base_url/$artifact_name-#{version}-#{arch}.dmg",
      verified: "$verified_url"
  name "apple-gateway"
  desc "$project_description"
  homepage "https://github.com/$github_repository"

  livecheck do
    url :url
    strategy :github_latest
  end

  binary "$product"
  binary "$reader_product"
  artifact "libexec/$notifier_app", target: "#{HOMEBREW_PREFIX}/libexec/$notifier_app"
  caveats do
    <<~EOS
      This cask installs the signed and notarized macOS command line tools,
      and the AppleGatewayNotifier helper app.
      Homebrew links $product and $reader_product into the native Homebrew
      prefix for this Mac.
    EOS
  end
end
EOF

  printf 'rendered %s\n' "$output"
}

main "$@"
