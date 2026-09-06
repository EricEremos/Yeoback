#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swiftc -O -parse-as-library Sources/Cleanup/WorkArtifact.swift Sources/Cleanup/Storage.swift Sources/Cleanup/CacheCleanup.swift Sources/Cleanup/StorageForecast.swift Sources/Cleanup/LocalStorageAdvisor.swift scripts/ForecastCheck.swift -o .build/cleanup-forecast-check
.build/cleanup-forecast-check "$@"
