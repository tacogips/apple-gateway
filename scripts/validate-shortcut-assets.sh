#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
shortcuts_dir="${APPLE_GATEWAY_SHORTCUTS_DIR:-$repo_root/packaging/shortcuts}"
manifest_path="$shortcuts_dir/manifest.json"
allow_missing="${APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS:-}"

usage() {
  cat <<EOF
Usage:
  scripts/validate-shortcut-assets.sh

Validates that packaging/shortcuts contains every exported .shortcut file
declared by packaging/shortcuts/manifest.json.

Environment:
  APPLE_GATEWAY_SHORTCUTS_DIR                         Override shortcuts directory.
  APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1   Allow missing .shortcut files for incomplete local/manual runs only.

Production release packaging must not set
APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS.
EOF
}

shortcut_files_from_manifest() {
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
    print(f"{name}.shortcut")
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
        puts "#{name}.shortcut"
      end
    ' "$manifest_path"
    return
  fi

  printf 'missing JSON parser: expected python3 or ruby\n' >&2
  return 1
}

is_allow_missing_enabled() {
  case "$allow_missing" in
    1 | true | TRUE | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return
  fi
  if [[ "$#" -ne 0 ]]; then
    usage >&2
    return 2
  fi
  if [[ ! -f "$manifest_path" ]]; then
    printf 'missing shortcut manifest: %s\n' "$manifest_path" >&2
    return 1
  fi

  local -a expected_files missing_files
  local manifest_files
  local shortcut_file
  expected_files=()
  missing_files=()

  manifest_files="$(shortcut_files_from_manifest)"
  while IFS= read -r shortcut_file; do
    if [[ -z "$shortcut_file" ]]; then
      continue
    fi
    expected_files+=("$shortcut_file")
  done <<< "$manifest_files"

  if [[ "${#expected_files[@]}" -eq 0 ]]; then
    printf 'shortcut manifest did not declare any shortcut files: %s\n' "$manifest_path" >&2
    return 1
  fi

  for shortcut_file in "${expected_files[@]}"; do
    if [[ ! -f "$shortcuts_dir/$shortcut_file" ]]; then
      missing_files+=("$shortcut_file")
    fi
  done

  if [[ "${#missing_files[@]}" -eq 0 ]]; then
    printf 'validated %s shortcut asset(s) in %s\n' "${#expected_files[@]}" "$shortcuts_dir"
    return
  fi

  printf 'missing exported shortcut asset(s): %s\n' "${missing_files[*]}" >&2
  printf 'expected files are declared by %s\n' "$manifest_path" >&2
  printf 'export the real .shortcut files from Shortcuts.app; do not create placeholder files.\n' >&2

  if is_allow_missing_enabled; then
    printf 'bypass enabled: APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1; continuing for incomplete local/manual run only.\n' >&2
    return
  fi

  printf 'release packaging refused because bridge shortcut exports are incomplete.\n' >&2
  printf 'for non-release local checks only, rerun with APPLE_GATEWAY_ALLOW_INCOMPLETE_SHORTCUT_EXPORTS=1.\n' >&2
  return 1
}

main "$@"
