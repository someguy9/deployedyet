#!/usr/bin/env bash
# Build and (re)launch the menu bar app without opening Xcode.
set -euo pipefail
cd "$(dirname "$0")"
export TUIST_SKIP_UPDATE_CHECK=1
pkill -x DeployedYet 2>/dev/null || true
while pgrep -x DeployedYet >/dev/null; do sleep 0.2; done # `open` on a dying instance just activates it
tuist generate --no-open
tuist xcodebuild build -scheme DeployedYet -configuration Debug -derivedDataPath Derived -quiet
APP=Derived/Build/Products/Debug/DeployedYet.app
open "$APP"
# LaunchServices occasionally drops the first open right after a rebuild; retry once.
for _ in $(seq 20); do pgrep -x DeployedYet >/dev/null && exit 0; sleep 0.5; done
open "$APP"
