# BulkTrack

An iPhone tracker for calories, macros, water, creatine, sleep, gym attendance and weight gain. Local SwiftData storage, Apple Health integration and Swift Charts. No subscriptions, server or third-party dependencies.

## Run

1. Open **BulkTrack.xcodeproj** in Xcode.
2. Select **BulkTrack** and an iPhone simulator, then press **⌘R**.
3. For a real iPhone, choose your signing team and unique bundle identifier under **Signing & Capabilities**, select the phone, and run.
4. Confirm your profile measurements and goals. Tap **Connect Apple Health** for energy and sleep reads.

Deployment target: **iOS 17+**. The final build was checked with Xcode 27.0. HealthKit capability, entitlement and privacy descriptions are included.

## Version 1.1 polish

- **Today:** a focused calorie/protein summary, workout entry point, compact habits and latest weight. Teal and lime are used consistently, with native navigation, dark appearance, larger-text layouts, quiet animations and Reduce Motion support.
- **Nutrition:** browse past days, edit food and habits, delete with Undo, repeat a meal, reuse recent/favorite foods, and adjust servings before saving. Incomplete macros remain unknown. Calendar meals are expandable suggestions rather than automatic diary entries.
- **Training:** start/resume/finish guided workouts, reuse prior loads, record sets, rest with a saved deadline, and review history. Routine snapshots keep past workouts intact after exercise edits. Add/edit/reorder/remove exercises, move or swap planned days, and extend the schedule.
- **Progress:** weekly averages, weight/energy charts, full weigh-in history, editing/deletion with Undo, and explicit Health export. Editing an exported measurement advances its sync version before a new export.
- **Settings:** profile and goals, Health readings and refresh status, local storage information, complete JSON backup, and a reviewed restore that merges entries without erasing unrelated data.
- All numeric forms include keyboard **Done** and scroll dismissal. Resting Calories uses a clear automatic/manual switch. Correctly grouped numeric input such as **1,700** is accepted.

To update the installed app, open this project, select your iPhone and press **⌘R**. Keep the existing bundle identifier so iOS updates the app and retains its diary. Use Settings → Export complete backup to keep your own copy.

### US units

Height entry is **feet and inches**. Body weight, target weight, workout loads, chart labels and accessibility descriptions use **pounds**. Water uses **US fluid ounces**, with **+8 oz** and **+16 oz** shortcuts.

Calories and nutrition grams follow US nutrition-label conventions. Creatine stays in grams to avoid an awkward or misleading dose conversion.

The underlying store still uses kilograms, centimeters and milliliters. **USUnits** converts at the UI boundary; existing weight and habit records are not relabeled or rewritten. Exported HealthKit weights still use a compatible kilogram unit. Editable values are rounded for display; saving a goal explicitly uses the displayed US value.

## Your calendar plan

The personal plan was read from the **Fitness** calendar in Apple Calendar on **October 14, 2026**. An older fitness conversation was ruled out by the user and its targets and exercises were removed. No 118/125/130/135 lb targets from that conversation are applied. Existing body measurements, goal weight, birthday, food history and daily calorie settings are preserved.

This is a **saved snapshot**, not live calendar synchronization. Editing Apple Calendar later does not automatically update this app.

### Workouts

The actual calendar starts with **Workout A, Friday October 16, 10 AM, McComas Hall**, followed by **Workout B on Monday October 19**. A/B alternate on Monday, Wednesday and Friday through **Wednesday November 11**.

| A exercise | Normal sets | Target |
| --- | --- | --- |
| Leg press | 3 | 8–12 reps |
| Dumbbell bench press | 3 | 8–12 reps |
| Seated cable row | 3 | 8–12 reps |
| Dumbbell Romanian deadlift | 2 | 8–10 reps |
| Plank | 2 | 30–45 seconds |

| B exercise | Normal sets | Target |
| --- | --- | --- |
| Goblet squat | 3 | 8–12 reps |
| Lat pulldown | 3 | 8–12 reps |
| Incline dumbbell press | 3 | 8–12 reps |
| Seated leg curl | 2 | 10–15 reps |
| Lateral raise | 2 | 12–15 reps |

The calendar's first-week instruction is **two working sets per exercise**, October 16–22. Its warm-up, rest and progression notes appear in Training. Timed plank sets use seconds, not reps.

A one-time local import adds these exercises and sets the calendar rhythm and its October 16 anchor. Training now supports edits to individual planned days, moves/swaps and an editable end date. It does not invent completed sessions or measurements. The schedule ends with the recorded calendar plan. Profile includes **Continue this rhythm after the plan** and an alternative **Two on, one off** schedule. Changing schedules starts a new streak without deleting previous attendance.

Workout sets belong to a saved session, while earlier standalone sets remain accessible. Finishing a guided workout logs the visit; a calendar check-in can also record attendance without creating sets. A planned workout never counts as attended automatically. Rest days preserve the streak; missed scheduled sessions break it after the tracking day ends.

### Meals

| Slot | Time | Calendar notes |
| --- | --- | --- |
| Breakfast | 8:30 AM | Dorm oats/milk/peanut butter/banana/yogurt; Turner/Perry alternatives |
| Pre-class snack | 10:15 AM Tue/Thu | Optional; may replace evening snack |
| Lunch | Noon; 2:15 PM Tue/Thu | Turner, with Perry/West End backups |
| Shake / afternoon snack | 4:15 PM | Optional; needed calories only; use the actual product label |
| Dinner | 7 PM | West End JP's, with Turner/Perry backups |
| Evening snack | 9:30 PM | Optional; skip when the daily target is met |

The app includes the calendar's pork-free preferences and venue alternatives. The notes' calorie and protein ranges are labeled **calendar estimates**, not verified live menus or product formulas. Venue hours, ingredients and portions can change.

Tapping a meal opens its suggestions and a food entry. The app does **not** automatically mark a planned meal as eaten. Enter actual portion/label nutrition before saving. Optional shakes and snacks never become automatic calories. Partial macros, such as protein only, can be logged while unknown carbs/fat remain unknown.

## Architecture

~~~
BulkTrackApp → local ModelContainer + observable HealthKitManager
             → RootView → one-time calendar template import
                 → DashboardView: Today / Nutrition / Training / Progress
                     → validated US-unit entry forms → DiaryStore → SwiftData
                     → TrainingPlanView + guided WorkoutSessionView + editable calendar
                     → ProgressChartsView
                     → SettingsView → validated JSON capture/merge

Core: CalorieEngine, TrackingCalendar, Routine, SleepIntervals,
      USUnits, WeightTrend, CalendarFitnessPlan, TrainingSchedule, BackupSnapshot
~~~

Models: **UserProfile, DailyLog, FoodEntry, WeightEntry, TrainingExercise, WorkoutSet, WorkoutSession, WorkoutScheduleOverride**.

New persisted fields have defaults for existing-store migration. Daily food relationships retain their explicit inverse and cascade deletion. All mutations run on the main actor, save explicitly and report failures. The calendar template is imported once per profile, without replacing diary measurements.

## Energy and HealthKit

The algorithm remains:

~~~
R = Mifflin–St Jeor estimate from current weight, height and age,
    or the user's custom resting estimate

projectedResting = max(R, recordedBasalSoFar + R × remainingDayFraction)
projectedActive  = max(activityAllowance, recordedActiveSoFar)
target           = projectedResting + projectedActive + configuredSurplus
~~~

The surplus becomes zero at the profile's final goal. Recorded active energy replaces a lower allowance; it is not added again as exercise calories. Missing Health readings remain unknown in the UI. Estimates cannot guarantee a physiologically exact surplus.

An optional fixed daily protein goal can be edited in grams. Existing profiles keep their prior weight-based protein calculation until a daily goal is saved. Fat and carbs use the remaining energy budget. A calorie-only or partially specified food entry is clearly identified as having incomplete macros.

HealthKit reads active energy, basal energy and sleep. Apple hides read-denial status, so a finished permission request is not treated as a guarantee of access. Energy queries use cumulative statistics. Overlapping asleep intervals are clipped to the noon-to-noon recovery window and merged. Awake/in-bed samples are excluded.

Refresh occurs on activation, pull-to-refresh, observer changes and once per minute while active. There is no background-delivery entitlement or suspended-app refresh guarantee. Health snapshots stay in memory and are replaced on refresh, so removed/unavailable data does not remain displayed as a current reading.

Weight write permission is requested separately, only for explicit export. Stable sync identifiers make retrying an entry safe. Food, water, creatine and plan data remain local.

Dates use a Gregorian calendar in the tracking zone selected during setup, with calendar-day arithmetic across daylight saving changes.

## Weight and energy charts

Weekly weight averages first average measurements within each day, then average measured days; repeated same-day readings do not receive extra influence. Week-to-week change appears when both weeks have at least three measured days. Gaps remain gaps.

The 30/90-day weight chart uses pounds, a goal line and touch selection. The 7-day grouped bars compare logged Calories eaten against recorded active + resting Calories burned. Today is partial, and historical reads may also be incomplete. Those bars are not full-day projections.

## Verification

Run the deterministic checks from this directory:

~~~sh
sh test-core.sh
sh test-persistence.sh
sh test-backup.sh
~~~

The core suite covers calorie calculations, missing Health readings, US conversions, input validation, DST/day boundaries, sleep overlap, schedule overrides/streaks, weight averages, rest deadlines, saved routines and backup validation. The persistence suite seeds the previous schema in a temporary SQLite store, migrates it, then reopens it in another process. Backup integration checks exercise JSON round trips, ID merges, food relationships, retained unrelated entries, Health revision handling and rejected imports. These tests do not open your live diary.

Simulator UI tests are included in the **BulkTrack** scheme. Choose an iPhone simulator and press **⌘U**. The tests launch with an isolated in-memory diary; test records never enter the normal local store and Health is disabled for this test launch. They exercise food/weight entry and editing, keyboard dismissal, guided workout resume/finish, Settings and large-text/dark layouts. Normal **⌘R** opens your real diary.

Build without signing:

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BulkTrack.xcodeproj -scheme BulkTrack \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
~~~

See **QA.md** for the latest results and remaining device checks. Real Apple Health permission changes/reads/writes and signed iPhone installation require a physical device.

## API references

- [Apple: HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Apple: async statistics collection queries](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquerydescriptor)
- [Apple: sleep analysis values](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)
- [Apple: HealthKit sync identifiers](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)
- [Apple: SwiftData relationships](https://developer.apple.com/documentation/swiftdata/defining-data-relationships-with-enumerations-and-model-classes)
- [Mifflin et al.: resting energy equation](https://pubmed.ncbi.nlm.nih.gov/2305711/)

### Custom exercise logging

Open Training → Log any exercise to record a name, weight in pounds, reps, and matching sets. Use another entry when the weight or reps change. Optionally mark the date as a gym visit. Open Exercise log to review, edit a set, or swipe to delete it.
