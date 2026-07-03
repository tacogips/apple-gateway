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
  scripts/render-homebrew-formula.sh <version> [output-file]

Reads archive checksums from:
  dist/homebrew/$artifact_name-<version>-<target>.tar.gz.sha256

Environment:
  RELEASE_DIR       Directory containing archives and .sha256 files.
  RELEASE_BASE_URL  Release URL base. Defaults to GitHub v<version>.

Example:
  scripts/build-homebrew-release.sh darwin-arm64 darwin-x64
  scripts/render-homebrew-formula.sh 0.1.0 Formula/$artifact_name.rb

This renderer expects Swift macOS release archives. Linux archives are
unsupported until the project defines a reviewed Swift Linux build contract.
EOF
}

sha_for_target() {
  local version target release_dir sha_file
  version="$1"
  target="$2"
  release_dir="$3"
  sha_file="$release_dir/$artifact_name-$version-$target.tar.gz.sha256"

  if [[ ! -f "$sha_file" ]]; then
    printf 'missing checksum file: %s\n' "$sha_file" >&2
    return 1
  fi

  awk '{print $1}' "$sha_file"
}

shortcut_assertions_from_manifest() {
  local manifest_path
  manifest_path="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$manifest_path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)

shortcuts = manifest.get("shortcuts")
if not isinstance(shortcuts, list) or not shortcuts:
    raise SystemExit("manifest shortcuts must be a non-empty array")

for shortcut in shortcuts:
    name = shortcut.get("name") if isinstance(shortcut, dict) else None
    if not isinstance(name, str) or not name:
        raise SystemExit("manifest shortcut entries must include non-empty name strings")
    print(f"    assert_path_exists pkgshare/{json.dumps('shortcuts/' + name + '.shortcut')}")
PY
    return
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
      manifest = JSON.parse(File.read(ARGV.fetch(0)))
      shortcuts = manifest["shortcuts"]
      abort("manifest shortcuts must be a non-empty array") unless shortcuts.is_a?(Array) && !shortcuts.empty?
      shortcuts.each do |shortcut|
        name = shortcut.is_a?(Hash) ? shortcut["name"] : nil
        abort("manifest shortcut entries must include non-empty name strings") unless name.is_a?(String) && !name.empty?
        puts "    assert_path_exists pkgshare/#{("shortcuts/" + name + ".shortcut").inspect}"
      end
    ' "$manifest_path"
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

  local version output release_dir release_base_url
  version="$1"
  output="${2:-$repo_root/Formula/$artifact_name.rb}"
  release_dir="${RELEASE_DIR:-$repo_root/dist/homebrew}"
  release_base_url="${RELEASE_BASE_URL:-https://github.com/$github_repository/releases/download/v$version}"

  local shortcut_manifest shortcut_assertions
  shortcut_manifest="$repo_root/packaging/shortcuts/manifest.json"
  if [[ ! -f "$shortcut_manifest" ]]; then
    printf 'missing shortcut manifest: %s\n' "$shortcut_manifest" >&2
    return 1
  fi
  shortcut_assertions="$(shortcut_assertions_from_manifest "$shortcut_manifest")"

  local darwin_arm64_sha darwin_x64_sha
  darwin_arm64_sha="$(sha_for_target "$version" darwin-arm64 "$release_dir")"
  darwin_x64_sha="$(sha_for_target "$version" darwin-x64 "$release_dir")"

  mkdir -p "$(dirname "$output")"
  cat > "$output" <<EOF
class AppleGateway < Formula
  desc "$project_description"
  homepage "https://github.com/$github_repository"
  version "$version"
  license "MIT"

  livecheck do
    url :stable
    strategy :github_latest
  end

  on_macos do
    if Hardware::CPU.arm?
      url "$release_base_url/$artifact_name-$version-darwin-arm64.tar.gz"
      sha256 "$darwin_arm64_sha"
    else
      url "$release_base_url/$artifact_name-$version-darwin-x64.tar.gz"
      sha256 "$darwin_x64_sha"
    end
  end

  def install
    bin.install "bin/$product"
    bin.install "bin/$reader_product"
    libexec.install "libexec/$notifier_app"
    pkgshare.install "share/$artifact_name/shortcuts"
  end

  test do
    assert_match "$version", shell_output("#{bin}/$product --version")
    assert_match "$version", shell_output("#{bin}/$reader_product --version")
    assert_path_exists libexec/"$notifier_app"
    assert_path_exists pkgshare/"shortcuts/README.md"
    assert_path_exists pkgshare/"shortcuts/SOURCE.md"
    assert_path_exists pkgshare/"shortcuts/manifest.json"
$shortcut_assertions
  end
end
EOF

  printf 'rendered %s\n' "$output"
}

main "$@"
