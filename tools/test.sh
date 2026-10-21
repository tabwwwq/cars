#!/usr/bin/env bash
# Runs the Luau test suite (car builder, physics simulation, server systems,
# client smoke test) outside Roblox. Needs Rust (cargo) the first time.
#   tools/test.sh            all tests
#   tools/test.sh physics    only tests/physics.spec.luau
set -euo pipefail
cd "$(dirname "$0")/.."
RUNNER=tools/luau-runner/target/release/luaurun
if [ ! -x "$RUNNER" ]; then
  cargo build --release --manifest-path tools/luau-runner/Cargo.toml
fi
mkdir -p tests/out
"$RUNNER" run tests/run.luau "$@"
