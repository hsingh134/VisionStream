#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_cache="${TMPDIR:-/tmp}/visionstream-core-checks"
mkdir -p "$task_cache/modules"
CLANG_MODULE_CACHE_PATH="$task_cache/modules" swiftc -swift-version 6 -D VISIONSTREAM_STANDALONE \
    -module-cache-path "$task_cache/modules" \
    VisionStream/Core/*.swift Tests/CoreTests/*.swift Tests/Standalone/CoreTestRunner.swift \
    -o "$task_cache/core-checks"
"$task_cache/core-checks"
