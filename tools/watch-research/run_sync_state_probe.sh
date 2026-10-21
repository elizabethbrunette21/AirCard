#!/bin/bash
# Use an isolated simulator set; never select a real or pre-existing device.
set -euo pipefail

probe_root=$(cd "$(dirname "$0")/../.." && pwd)
probe_sdk=$(xcrun --sdk watchsimulator --show-sdk-path)
mkdir -p "$probe_root/build"
xcrun clang -target arm64-apple-watchos26.0-simulator -isysroot "$probe_sdk" \
    -fobjc-arc -O2 -Wall -Wextra -framework Foundation \
    "$probe_root/tools/watch-research/sync_state_probe.m" \
    -o "$probe_root/build/watch_sync_state_probe"

probe_set=$(mktemp -d /private/tmp/aircard-watch-sync.XXXXXX)
probe_id=''
cleanup() {
    if [ -n "$probe_id" ]; then
        xcrun simctl --set "$probe_set" shutdown "$probe_id" >/dev/null 2>&1 || true
        if ! xcrun simctl --set "$probe_set" delete "$probe_id"; then
            echo "Temporary simulator cleanup failed; retained set: $probe_set" >&2
            return 1
        fi
    fi
    rm -rf "$probe_set"
}
trap cleanup EXIT

probe_id=$(xcrun simctl --set "$probe_set" create 'Watch Sync Research' \
    com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm \
    com.apple.CoreSimulator.SimRuntime.watchOS-26-5)
xcrun simctl --set "$probe_set" boot "$probe_id"
xcrun simctl --set "$probe_set" spawn "$probe_id" "$probe_root/build/watch_sync_state_probe"
