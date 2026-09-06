#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swiftc -O -parse-as-library Sources/Cleanup/WorkArtifact.swift Sources/Cleanup/Storage.swift Sources/Cleanup/CacheCleanup.swift scripts/ProviderCheck.swift -o .build/cleanup-provider-check
.build/cleanup-provider-check "$@"
