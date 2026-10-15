#!/bin/sh
# Fallback test runner for machines with Command Line Tools only (SwiftPM broken there).
# With full Xcode use: cd ResetCore && swift test
set -e
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools
OUT=${TMPDIR:-/tmp}/resetcore-tests
mkdir -p "$OUT"
swiftc -swift-version 5 -enable-testing -parse-as-library -emit-library -static \
  -module-name ResetCore -emit-module -emit-module-path "$OUT/ResetCore.swiftmodule" \
  -o "$OUT/libResetCore.a" ResetCore/Sources/ResetCore/*.swift
swiftc -parse-as-library -swift-version 5 -o "$OUT/run" -I "$OUT" -L "$OUT" -lResetCore \
  -F $CLT/Library/Developer/Frameworks \
  -plugin-path $CLT/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker $CLT/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib \
  ResetCore/Tests/ResetCoreTests/*.swift scripts/widget-tests/*.swift Shared/WidgetShared.swift scripts/TestMain.swift
"$OUT/run"
