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

shortcut_caveat_lines_from_manifest() {
  local manifest_path artifact
  manifest_path="$1"
  artifact="$2"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$manifest_path" "$artifact" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)

artifact = sys.argv[2]
shortcuts = manifest.get("shortcuts")
if not isinstance(shortcuts, list) or not shortcuts:
    raise SystemExit("manifest shortcuts must be a non-empty array")

for shortcut in shortcuts:
    name = shortcut.get("name") if isinstance(shortcut, dict) else None
    if not isinstance(name, str) or not name:
        raise SystemExit("manifest shortcut entries must include non-empty name strings")
    print(f"        #{{HOMEBREW_PREFIX}}/share/{artifact}/shortcuts/{name}.shortcut")
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
      manifest = JSON.parse(File.read(ARGV.fetch(0)))
      artifact = ARGV.fetch(1)
      shortcuts = manifest["shortcuts"]
      abort("manifest shortcuts must be a non-empty array") unless shortcuts.is_a?(Array) && !shortcuts.empty?
      shortcuts.each do |shortcut|
        name = shortcut.is_a?(Hash) ? shortcut["name"] : nil
        abort("manifest shortcut entries must include non-empty name strings") unless name.is_a?(String) && !name.empty?
        puts "        \#{HOMEBREW_PREFIX}/share/#{artifact}/shortcuts/#{name}.shortcut"
      end
    ' "$manifest_path" "$artifact"
    return
  fi

  printf 'missing JSON parser: expected python3 or ruby\n' >&2
  return 1
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

  local shortcut_manifest shortcut_caveat_lines
  shortcut_manifest="$repo_root/packaging/shortcuts/manifest.json"
  if [[ ! -f "$shortcut_manifest" ]]; then
    printf 'missing shortcut manifest: %s\n' "$shortcut_manifest" >&2
    return 1
  fi
  shortcut_caveat_lines="$(shortcut_caveat_lines_from_manifest "$shortcut_manifest" "$artifact_name")"

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
  artifact "share/$artifact_name/shortcuts", target: "#{HOMEBREW_PREFIX}/share/$artifact_name/shortcuts"

  zap trash: "#{HOMEBREW_PREFIX}/share/$artifact_name/shortcuts"

  caveats do
    <<~EOS
      This cask installs the signed and notarized macOS command line tools,
      the AppleGatewayNotifier helper app, and the Clock alarm Shortcuts
      bridge package.
      Expected Clock alarm bridge package contents after release packaging:
        #{HOMEBREW_PREFIX}/share/$artifact_name/shortcuts/README.md
        #{HOMEBREW_PREFIX}/share/$artifact_name/shortcuts/SOURCE.md
        #{HOMEBREW_PREFIX}/share/$artifact_name/shortcuts/manifest.json
$shortcut_caveat_lines
      Homebrew links $product and $reader_product into the native Homebrew
      prefix for this Mac.
    EOS
  end
end
EOF

  printf 'rendered %s\n' "$output"
}

main "$@"
