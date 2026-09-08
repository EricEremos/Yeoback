#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swiftc -O -parse-as-library Sources/Cleanup/WorkArtifact.swift Sources/Cleanup/Storage.swift Sources/Cleanup/CacheCleanup.swift scripts/CacheInventoryCheck.swift -o .build/cleanup-cache-inventory-check
.build/cleanup-cache-inventory-check "$@"
