# BulkTrack 1.1 verification

Checked October 15, 2026 with Xcode 27.0 and iOS 27.0 Simulator. Deployment target remains iOS 17. The app's bundle identifier and signing team remain unchanged.

| Check | Result |
| --- | --- |
| Core calculations and backup validation | 118 passed |
| Previous-schema migration and reopened SQLite store | 31 passed, plus legacy seed verification |
| SwiftData backup round trips and merges | 15 passed |
| Simulator UI tests | 4 passed, 0 failures |
| Release build for generic iPhone, without signing | Succeeded |
| Project/Info plist validation and Swift source registration | Passed |

164 logic/storage assertions plus four UI flows passed. The tests use temporary stores or an in-memory diary. They do not open the normal diary or access real Health data.

## What the tests cover

- Calorie estimates, missing-versus-zero energy, macro accounting, US conversions, grouped input, DST, sleep overlap and weekly weight averaging.
- Imported calendar boundaries, moved/skipped days, streaks, rest deadlines and saved exercise snapshots.
- Migration retaining existing profile values, diary entries, measurements, identifiers and relationships. Moving food between days does not cause cascade deletion.
- Backup encoding/decoding, nil macros, favorites, full model fields, stable-ID upserts, repeated restores, unrelated-entry retention, weight export versions, invalid input rejection, mismatched diary time zones and unfinished-workout conflicts.
- UI: add/edit food, dismiss the actual keyboard with Done, open Settings, switch automatic/manual resting Calories, save a weigh-in, navigate dark/large-text layouts, start/log/rest/close/resume/finish a workout and confirm attendance.

Review also corrected stale water Undo after a history edit, habit edits spanning midnight, creatine day rollover, Undo after restoring the same UUID, and deleting a weight during an asynchronous Health export. Existing workout histories retain saved names/order/goals after routine edits.

## Preview

[Today](Preview/Today.png) and [large-text dark appearance](Preview/Today-accessibility-dark.png) are native simulator screenshots with test data, not your personal measurements.

## Reproduce

Run `sh test-core.sh`, `sh test-persistence.sh`, and `sh test-backup.sh`. In Xcode, select an iPhone simulator and press Command-U for the UI suite. Command-R uses the normal diary; only the UI test launch argument creates the isolated fixture.

The last UI result bundle is `.build/PolishUITests4.xcresult`; build/test logs are in `.build/`. Build outputs are intentionally omitted from the ZIP. Xcode's optional simulator diagnostic collector reported a `simctl` lookup warning because the Mac's global developer directory points at Command Line Tools. The test runner completed all tests successfully. The build's only warning was skipped App Intents metadata because this app does not use App Intents.

## Physical device checks

Signed installation, actual Health read/write authorization, permission revocation, energy aggregation from real devices and sleep sync still need a physical iPhone. These cannot be confirmed by a simulator fixture. Update using the existing bundle identifier; deleting the app removes its local diary.

## Custom exercise logging follow-up

Simulator build and the targeted `testCustomExerciseLogging` UI test passed. Verified empty-input Save is disabled, custom name/25 lb/12 reps saves, keyboard Done dismisses, history displays the saved values, and the saved set opens for editing. Log: `.build/custom-ui-test.log`. Existing model and backup format retained.
