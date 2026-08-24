#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d /tmp/omatris-hotkey-test.XXXXXX)
trap 'rm -rf -- "$test_dir"' EXIT

bindings_file="$test_dir/bindings.lua"
binds_json="$test_dir/binds.json"
printf '%s\n' '-- user bindings' > "$bindings_file"
printf '%s\n' '[{"modmask":64,"key":"F","description":"Full screen","submap":"","mouse":false}]' > "$binds_json"

run_helper() {
  OMATRIS_BINDINGS_FILE="$bindings_file" \
  OMATRIS_BINDS_JSON="$binds_json" \
    OMATRIS_SKIP_RELOAD=1 \
    OMATRIS_SKIP_CAPTURE=1 \
    bash "$project_dir/scripts/omatris-hotkey" "$@"
}

if conflict=$(run_helper set 'SUPER + F'); then
  echo "Expected occupied hotkey to be rejected" >&2
  exit 1
fi
[[ $(jq -r '.status' <<< "$conflict") == conflict ]]
[[ $(jq -r '.message' <<< "$conflict") == 'Already used by: Full screen' ]]
! grep -q 'BEGIN OMATRIS' "$bindings_file"

saved=$(run_helper set 'SUPER + SHIFT + G')
[[ $(jq -r '.status' <<< "$saved") == ok ]]
[[ $(jq -r '.shortcut' <<< "$saved") == 'SUPER + SHIFT + G' ]]
grep -q 'Open Omatris' "$bindings_file"
[[ $(run_helper get | jq -r '.shortcut') == 'SUPER + SHIFT + G' ]]
run_helper capture-on >/dev/null
grep -q 'hl.define_submap("omatris_capture"' "$bindings_file"
grep -q 'hl.bind("code:0"' "$bindings_file"

run_helper set 'CTRL + ALT + O' >/dev/null
[[ $(grep -c '^-- BEGIN OMATRIS HOTKEY$' "$bindings_file") == 1 ]]
[[ $(run_helper get | jq -r '.shortcut') == 'CTRL + ALT + O' ]]

cleared=$(run_helper clear)
[[ $(jq -r '.shortcut' <<< "$cleared") == '' ]]
grep -q 'BEGIN OMATRIS' "$bindings_file"
grep -q 'hl.define_submap("omatris_capture"' "$bindings_file"
! grep -q 'Open Omatris' "$bindings_file"
grep -q '^-- user bindings$' "$bindings_file"

if invalid=$(run_helper set 'SHIFT + Q'); then
  echo "Expected a Shift-only hotkey to be rejected" >&2
  exit 1
fi
[[ $(jq -r '.status' <<< "$invalid") == invalid ]]

echo "Hotkey helper tests passed"
