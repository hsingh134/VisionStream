#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_cache="${TMPDIR:-/tmp}/visionstream-video-quality"
mkdir -p "$task_cache/modules" TestResults
task_report="${1:-$PWD/TestResults/video-quality-gpu.json}"
swiftc -O -swift-version 6 -parse-as-library -module-cache-path "$task_cache/modules" \
    VisionStream/Core/Projection.swift VisionStream/Core/VideoImageQuality.swift \
    Tests/Quality/VideoQualityGPUChecks.swift Tests/MacVideoQualityProbe.swift \
    -o "$task_cache/video-quality"
"$task_cache/video-quality" VisionStream/Rendering/StereoVideo.metal "$task_report"
