#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
xcodegen generate --spec project.yml

echo "Generated: $(pwd)/MarkFlow.xcodeproj"
echo "Build app with: xcodebuild -project MarkFlow.xcodeproj -scheme MarkFlowApp -configuration Debug -derivedDataPath ./.xcodebuild build"
