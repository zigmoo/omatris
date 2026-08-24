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
cp "$project_dir/Game.js" "$project_dir/Omatris.qml" "$project_dir/OverlayWindow.qml" "$runtime_dir/"
cp "$project_dir/dev/shell.qml" "$runtime_dir/shell.qml"

quickshell -p "$runtime_dir"
