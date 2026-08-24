#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

omarchy plugin validate "$project_dir"
node "$project_dir/tests/game.test.js"

echo "Omatris checks passed"
