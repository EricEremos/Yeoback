#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/mobile-core
swiftc -parse-as-library Sources/Cleanup/WorkArtifact.swift mobile/ios/Yeoback/FolderEngine.swift scripts/MobileCoreCheck.swift -o .build/mobile-core/check
.build/mobile-core/check
