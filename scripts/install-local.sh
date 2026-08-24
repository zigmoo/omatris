#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_id=$(jq -r '.id' "$project_dir/manifest.json")
install_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id"

omarchy plugin validate "$project_dir"
mkdir -p "$install_dir"

for runtime_file in manifest.json Game.js Omatris.qml OverlayWindow.qml BarWidget.qml; do
  install -m 0644 "$project_dir/$runtime_file" "$install_dir/$runtime_file"
done

if omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null
  echo "Installed and rescanned $plugin_id"
else
  echo "Installed $plugin_id; Omarchy will discover it when the shell starts"
fi

echo "$install_dir"
