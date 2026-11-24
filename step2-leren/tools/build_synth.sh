#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
arch=${1:-$(uname -m)}
build=${KEYSIGHT_BUILD_DIR:-"$project/build/synth-$arch"}
flags=()
case "$arch" in
    aarch64)
        if [[ $(uname -m) != aarch64 ]]; then
            flags+=(-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64
                "-DCMAKE_CXX_COMPILER=${KEYSIGHT_AARCH64_CXX:-aarch64-linux-gnu-g++}")
        fi ;;
    x86_64) [[ $(uname -m) == x86_64 ]] || { echo "Build x86_64 on an x86_64 host" >&2; exit 2; } ;;
    *) echo "Usage: $0 [x86_64|aarch64]" >&2; exit 2 ;;
esac
cmake -S "$project/native" -B "$build" -DCMAKE_BUILD_TYPE=Release -DKEYSIGHT_ARCH="$arch" "${flags[@]}"
cmake --build "$build" --target keysight_synth --parallel "${KEYSIGHT_JOBS:-4}"
