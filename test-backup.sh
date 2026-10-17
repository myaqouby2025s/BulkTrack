#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/backup-integration .build/module-cache
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun swiftc \
  -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path .build/module-cache BulkTrack/Core/*.swift \
  BulkTrack/Models.swift BulkTrack/DataBackup.swift Tests/BackupIntegration/main.swift \
  -o .build/backup-integration/checks
.build/backup-integration/checks
