#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build-cache
xcrun swiftc -swift-version 5 -module-cache-path .build-cache Sources/Detector.swift Tests/main.swift -o .build-cache/detector-tests
.build-cache/detector-tests
