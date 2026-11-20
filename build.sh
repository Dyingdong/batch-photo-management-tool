#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/批量管理照片软件.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

FLAGS=(-O -swift-version 5 -target arm64-apple-macosx13.0)

# GUI App
swiftc "${FLAGS[@]}" \
    "$ROOT/Sources/PhotoCore.swift" \
    "$ROOT/App/App.swift" \
    -o "$APP/Contents/MacOS/BatchPhotoManager"

# 稳定的指定要求（identifier 固定）：TCC 对文件夹的授权在重新编译后依然有效
codesign --force --deep --sign - \
    --requirements '=designated => identifier "local.workbuddy.batchphotomanager"' \
    "$APP" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "BUILT: $APP"
