#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

omarchy plugin validate "$project_dir"
node "$project_dir/tests/game.test.js"
node "$project_dir/tests/settings-navigation.test.js"
bash "$project_dir/tests/hotkey-helper.test.sh"

for runtime_file in AudioController.qml BoardEffects.qml SettingsNavigation.js scripts/omatris-hotkey assets/audio/music.ogg \
  assets/audio/move.wav assets/audio/rotate.wav assets/audio/hold.wav \
  assets/audio/lock.wav assets/audio/hard-drop.wav assets/audio/single.wav \
  assets/audio/double.wav assets/audio/triple.wav assets/audio/omatris.wav \
  assets/audio/tspin.wav assets/audio/game-over.wav; do
  test -s "$project_dir/$runtime_file"
done

echo "Omatris checks passed"
