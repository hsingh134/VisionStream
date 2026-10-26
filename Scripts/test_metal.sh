#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_cache="${TMPDIR:-/tmp}/visionstream-metal-checks"
mkdir -p "$task_cache/modules"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$task_cache/modules" \
    VisionStream/Core/Projection.swift Tests/MacMetalProbe.swift -o "$task_cache/metal-checks"
"$task_cache/metal-checks" VisionStream/Rendering/StereoVideo.metal
