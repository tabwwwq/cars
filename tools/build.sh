#!/usr/bin/env bash
# Builds the Studio files:
#   build/CarsGame.rbxlx  - a complete place, open it in Roblox Studio
#   build/CarsMode.rbxmx  - the same scripts as an insertable model + installer
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build default.project.json -o build/CarsGame.rbxlx
rojo build install.project.json -o build/CarsMode.rbxmx
echo "Built build/CarsGame.rbxlx and build/CarsMode.rbxmx"
