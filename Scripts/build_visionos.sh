#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
variant="${1:-simulator}"
case "$variant" in
    simulator) destination='generic/platform=visionOS Simulator'; sdk=xrsimulator; signing=YES ;;
    device) destination='generic/platform=visionOS'; sdk=xros; signing=NO ;;
    *) echo 'Usage: sh Scripts/build_visionos.sh [simulator|device]' >&2; exit 2 ;;
esac
task_build_root="${VISIONSTREAM_BUILD_ROOT:-$PWD/DerivedData}"
mkdir -p TestResults
log="TestResults/visionos-$variant-build.txt"
if /usr/bin/xcodebuild -project VisionStream.xcodeproj -scheme VisionStream \
    -configuration Debug -sdk "$sdk" -destination "$destination" \
    -derivedDataPath "$task_build_root" CODE_SIGNING_ALLOWED="$signing" CODE_SIGN_IDENTITY=- build > "$log" 2>&1; then
    echo "Build passed: $task_build_root/Build/Products/Debug-$sdk/VisionStream.app"
else
    tail -n 70 "$log"
    exit 1
fi
