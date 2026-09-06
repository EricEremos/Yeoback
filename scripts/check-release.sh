#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swiftc -O -parse-as-library Sources/Cleanup/WorkArtifact.swift Sources/Cleanup/Storage.swift Sources/Cleanup/CacheCleanup.swift Sources/Cleanup/InventoryFilter.swift Sources/Cleanup/CleanupExecutor.swift Sources/Cleanup/AppModel.swift Sources/Cleanup/AppDelegate.swift scripts/ReleaseCheck.swift -o .build/cleanup-release-check
.build/cleanup-release-check "$@"
