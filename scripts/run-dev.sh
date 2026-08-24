#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime_dir=$(mktemp -d /tmp/omatris-dev.XXXXXX)

cleanup() {
  rm -rf -- "$runtime_dir"
}
trap cleanup EXIT

omarchy plugin validate "$project_dir"

mkdir -p "$runtime_dir/Commons"
cp -a /usr/share/omarchy/shell/Commons/. "$runtime_dir/Commons/"
cp "$project_dir/Game.js" "$project_dir/Omatris.qml" "$project_dir/OverlayWindow.qml" \
  "$project_dir/BoardEffects.qml" "$project_dir/AudioController.qml" \
  "$project_dir/SettingsNavigation.js" "$runtime_dir/"
cp -a "$project_dir/assets" "$runtime_dir/assets"
mkdir -p "$runtime_dir/scripts"
cp "$project_dir/scripts/omatris-hotkey" "$runtime_dir/scripts/omatris-hotkey"
cp "$project_dir/dev/shell.qml" "$runtime_dir/shell.qml"

quickshell -p "$runtime_dir"
