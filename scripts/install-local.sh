#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_id=$(jq -r '.id' "$project_dir/manifest.json")
install_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id"

omarchy plugin validate "$project_dir"
mkdir -p "$install_dir"

for runtime_file in manifest.json Game.js SettingsNavigation.js Omatris.qml OverlayWindow.qml BoardEffects.qml AudioController.qml BarWidget.qml; do
  install -m 0644 "$project_dir/$runtime_file" "$install_dir/$runtime_file"
done

mkdir -p "$install_dir/assets/audio"
for audio_file in "$project_dir"/assets/audio/*; do
  install -m 0644 "$audio_file" "$install_dir/assets/audio/$(basename "$audio_file")"
done

mkdir -p "$install_dir/scripts"
install -m 0755 "$project_dir/scripts/omatris-hotkey" "$install_dir/scripts/omatris-hotkey"

if omarchy-shell shell ping >/dev/null 2>&1; then
  # A rescan refreshes plugin discovery but may retain already-instantiated
  # QML component types. Restart so changes to shared components are loaded.
  omarchy restart shell
  echo "Installed and restarted the shell for $plugin_id"
else
  echo "Installed $plugin_id; Omarchy will discover it when the shell starts"
fi

echo "$install_dir"
