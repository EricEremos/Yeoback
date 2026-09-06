#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swiftc -O -parse-as-library Sources/Cleanup/WorkArtifact.swift Sources/Cleanup/Storage.swift Sources/Cleanup/CacheCleanup.swift Sources/Cleanup/InventoryFilter.swift Sources/Cleanup/CleanupExecutor.swift Sources/Cleanup/AppModel.swift scripts/BatchCheck.swift -o .build/cleanup-batch-check
.build/cleanup-batch-check
