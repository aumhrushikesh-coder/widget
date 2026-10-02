#!/bin/bash
# Builds "MICA Schedule.app" and copies it to /Applications.
# Needs only the Xcode Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/MICA Schedule.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ScheduleWidget" "$APP/Contents/MacOS/ScheduleWidget"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "iPhone/MICA Schedule.js" "$APP/Contents/Resources/MICA Schedule.js"
codesign --force --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
    pkill -x ScheduleWidget 2>/dev/null || true
    rm -rf "/Applications/MICA Schedule.app"
    cp -R "$APP" /Applications/
    open "/Applications/MICA Schedule.app"
    echo "Installed and launched /Applications/MICA Schedule.app"
else
    echo "Built $APP"
fi
