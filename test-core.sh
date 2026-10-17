#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache BulkTrack/Core/*.swift Tests/main.swift Tests/BackupValidationChecks.swift -o .build/core-tests
.build/core-tests
