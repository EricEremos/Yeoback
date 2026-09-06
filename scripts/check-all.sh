#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swift build -c release
.build/release/Cleanup --self-check
zsh scripts/check-batch.sh
zsh scripts/check-release.sh
zsh scripts/check-provider.sh
zsh scripts/check-forecast.sh
swiftc -O -parse-as-library Sources/Cleanup/WorkArtifact.swift Sources/Cleanup/Storage.swift Sources/Cleanup/CacheCleanup.swift Sources/Cleanup/GrowthLedger.swift scripts/test-growth.swift -o .build/cleanup-growth-check
.build/cleanup-growth-check
