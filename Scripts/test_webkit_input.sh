#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p DerivedData
swiftc -swift-version 6 -parse-as-library Tests/MacWebIntent.swift -framework WebKit -framework AppKit -o DerivedData/MacWebIntent
DerivedData/MacWebIntent "$PWD"
