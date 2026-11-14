#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
product="AppleGatewayNotifier"
bundle_id="me.tacogips.apple-gateway.notifier"

usage() {
  cat <<EOF
Usage:
  scripts/build-notifier-app.sh [--dry-run] [--configuration debug|release] [--executable PATH] [--output PATH]

Environment:
  SWIFT_BIN                          Swift executable. Defaults to Xcode's Swift toolchain on macOS, then PATH.
  SWIFT_DEVELOPER_DIR                Defaults to /Applications/Xcode.app/Contents/Developer on macOS.
  SWIFT_SDKROOT                      Defaults to Xcode's macOS SDK path on macOS.
  APPLE_GATEWAY_NOTIFIER_SIGNING     Signing mode: none, ad-hoc, or identity. Defaults to none.
  APPLE_GATEWAY_NOTIFIER_IDENTITY    codesign identity when signing mode is identity.

This script assembles AppleGatewayNotifier.app locally. It does not notarize,
upload artifacts, mutate Homebrew/Cask scripts, or push commits.
EOF
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$repo_root" "$1" ;;
  esac
}

swift_bin() {
  if [[ -n "${SWIFT_BIN:-}" ]]; then
    printf '%s\n' "$SWIFT_BIN"
    return
  fi
  if [[ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift ]]; then
    printf '%s\n' "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    return
  fi
  command -v swift
}

print_plan() {
  local configuration executable output signing identity
  configuration="$1"
  executable="$2"
  output="$3"
  signing="$4"
  identity="$5"

  printf 'AppleGatewayNotifier app assembly plan\n'
  printf '  product: %s\n' "$product"
  printf '  bundle id: %s\n' "$bundle_id"
  printf '  configuration: %s\n' "$configuration"
  printf '  executable: %s\n' "${executable:-<build with swift>}"
  printf '  output bundle: %s\n' "$output"
  printf '  create: %s/Contents/MacOS/%s\n' "$output" "$product"
  printf '  create: %s/Contents/Info.plist\n' "$output"
  printf '  Info.plist LSUIElement: true\n'
  printf '  signing mode: %s\n' "$signing"
  if [[ "$signing" == "identity" ]]; then
    printf '  signing identity configured: %s\n' "$([[ -n "$identity" ]] && printf yes || printf no)"
  fi
}

build_executable() {
  local configuration swift_exe developer_dir sdkroot
  configuration="$1"
  swift_exe="$(swift_bin)"
  developer_dir="${SWIFT_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  sdkroot="${SWIFT_SDKROOT:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"

  (
    cd "$repo_root"
    DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" \
      "$swift_exe" build -c "$configuration" --product "$product" >/dev/null
    DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" \
      "$swift_exe" build -c "$configuration" --product "$product" --show-bin-path
  )
}

write_info_plist() {
  local path
  path="$1"

  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$product</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$product</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
  <key>CFBundleVersion</key>
  <string>0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF
}

sign_bundle() {
  local signing identity output
  signing="$1"
  identity="$2"
  output="$3"

  case "$signing" in
    none)
      return
      ;;
    ad-hoc)
      codesign --force --sign - "$output"
      ;;
    identity)
      if [[ -z "$identity" ]]; then
        printf 'APPLE_GATEWAY_NOTIFIER_IDENTITY is required when APPLE_GATEWAY_NOTIFIER_SIGNING=identity\n' >&2
        return 1
      fi
      codesign --force --options runtime --timestamp --sign "$identity" "$output"
      ;;
    *)
      printf 'unsupported signing mode: %s\n' "$signing" >&2
      return 1
      ;;
  esac
}

assemble_bundle() {
  local configuration executable output signing identity bin_path
  configuration="$1"
  executable="$2"
  output="$3"
  signing="$4"
  identity="$5"

  if [[ -z "$executable" ]]; then
    bin_path="$(build_executable "$configuration" | tail -n 1)"
    executable="$bin_path/$product"
  fi
  if [[ ! -x "$executable" ]]; then
    printf 'notifier executable not found or not executable: %s\n' "$executable" >&2
    return 1
  fi

  rm -rf "$output"
  mkdir -p "$output/Contents/MacOS"
  cp "$executable" "$output/Contents/MacOS/$product"
  chmod 0755 "$output/Contents/MacOS/$product"
  touch "$output/Contents/Info.plist"
  write_info_plist "$output/Contents/Info.plist"
  sign_bundle "$signing" "$identity" "$output"

  printf 'assembled %s\n' "$output"
}

main() {
  local dry_run configuration executable output signing identity
  dry_run=false
  configuration="debug"
  executable=""
  output="$repo_root/.build/$product.app"
  signing="${APPLE_GATEWAY_NOTIFIER_SIGNING:-none}"
  identity="${APPLE_GATEWAY_NOTIFIER_IDENTITY:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage
        return
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --configuration)
        configuration="${2:-}"
        shift 2
        ;;
      --executable)
        executable="$(absolute_path "${2:-}")"
        shift 2
        ;;
      --output)
        output="$(absolute_path "${2:-}")"
        shift 2
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  case "$configuration" in
    debug | release) ;;
    *)
      printf 'unsupported configuration: %s\n' "$configuration" >&2
      return 2
      ;;
  esac

  print_plan "$configuration" "$executable" "$output" "$signing" "$identity"
  if [[ "$dry_run" == true ]]; then
    return
  fi

  assemble_bundle "$configuration" "$executable" "$output" "$signing" "$identity"
}

main "$@"
