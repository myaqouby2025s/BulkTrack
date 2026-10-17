#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/module-cache .build/tests
persistence_dir=$(mktemp -d "$PWD/.build/tests/persistence.XXXXXX")
trap 'rm -rf "$persistence_dir"' EXIT HUP INT TERM
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
persistence_sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc -module-name BulkTrack -module-cache-path .build/module-cache -D LEGACY_SEED \
    -sdk "$persistence_sdk" -target "$(uname -m)-apple-macosx14.0" \
    Tests/Persistence/LegacyModels.swift BulkTrack/Core/CalorieEngine.swift BulkTrack/Core/TrackingCalendar.swift BulkTrack/Core/Routine.swift BulkTrack/Core/WorkoutPlan.swift Tests/Persistence/main.swift \
    -o "$persistence_dir/legacy-checks"
swiftc -module-name BulkTrack -module-cache-path .build/module-cache \
    -sdk "$persistence_sdk" -target "$(uname -m)-apple-macosx14.0" \
    BulkTrack/Models.swift BulkTrack/Core/CalorieEngine.swift BulkTrack/Core/TrackingCalendar.swift BulkTrack/Core/Routine.swift BulkTrack/Core/WorkoutPlan.swift Tests/Persistence/main.swift \
    -o "$persistence_dir/current-checks"
"$persistence_dir/legacy-checks" "$persistence_dir/diary.store" seed
"$persistence_dir/current-checks" "$persistence_dir/diary.store" migrate
"$persistence_dir/current-checks" "$persistence_dir/diary.store" reopen
