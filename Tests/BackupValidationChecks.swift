import Foundation

func runBackupValidationChecks() {
    let today = date("2026-10-15T12:00:00Z")
    let foodID = UUID(), sessionID = UUID(), exerciseID = UUID()
    let savedPlan = WorkoutExerciseSnapshot.encode([.init(id: exerciseID.uuidString, name: "Plank", sets: 2, repGoal: "30–45 sec")])
    let midnight = TrackingCalendar(timeZoneID: "America/New_York").start(of: today)
    let p = BackupSnapshot.Profile(key: "primary", heightCM: 175, initialWeightKG: 70, targetWeightKG: 80,
        birthDate: date("2000-01-01T12:00:00Z"), restingEquationRaw: "male", manualRestingKcal: 1700,
        plannedActiveKcal: 350, surplusKcal: 250, proteinGramsPerKG: 1.8, waterGoalML: 2500,
        creatineGoalGrams: 5, sleepGoalHours: 8, routineAnchor: today, trackingTimeZoneID: "America/New_York",
        routineModeRaw: "threeDayFullBody", proteinGoalGrams: 126, calendarPlanVersion: 1, routineEndDate: nil)
    let original = BackupSnapshot(createdAt: today, profile: p,
        days: [.init(dayKey: "2026-10-15", date: midnight, waterML: 500, creatineGrams: 5, gymAttended: true)],
        foods: [.init(id: foodID, name: "Oats", timestamp: today, calories: 400,
                      proteinGrams: 20, carbGrams: nil, fatGrams: 0, isFavorite: true, dayKey: "2026-10-15")],
        weights: [.init(id: UUID(), date: today, kilograms: 70.5, healthExportedAt: today, healthSyncVersion: 3)],
        exercises: [.init(id: exerciseID, name: "Plank", plannedSets: 2, repGoal: "30–45 sec",
                         workoutRaw: "Training A", addedAt: today, isCalendarImported: true, sortOrder: 3)],
        sets: [.init(id: UUID(), date: today, exerciseID: exerciseID.uuidString, exerciseName: "Plank",
                    kilograms: 0, reps: 40, unitRaw: "seconds", sessionID: sessionID)],
        sessions: [.init(id: sessionID, startedAt: today, endedAt: today.addingTimeInterval(1800),
                        workoutRaw: "Training A", dayKey: "2026-10-15", restEndsAt: today.addingTimeInterval(60), planSnapshotJSON: savedPlan)],
        schedule: [.init(dayKey: "2026-10-15", date: midnight, phaseRaw: "Training A")])
    func rejected(_ snapshot: BackupSnapshot) -> Bool {
        do { try snapshot.validate(); return false } catch { return true }
    }
    do {
        let decoded = try BackupSnapshot.decode(original.encoded())
        expect(decoded.recordCount == 7, "Backup round trip retains every record category")
        expect(decoded.foods[0].carbGrams == nil && decoded.foods[0].fatGrams == 0,
               "Backup preserves unknown macros separately from zero")
        expect(decoded.foods[0].id == foodID && decoded.foods[0].isFavorite,
               "Backup preserves stable food identity and favorites")
        expect(decoded.sets[0].unitRaw == "seconds" && decoded.sets[0].sessionID == sessionID,
               "Backup preserves timed sets and session links")
        expect(decoded.exercises[0].sortOrder == 3, "Backup preserves custom exercise order")
        expect(decoded.sessions[0].planSnapshotJSON == savedPlan, "Backup preserves the routine captured at workout start")
        expect(decoded.weights[0].healthSyncVersion == 3 && decoded.sets[0].exerciseName == "Plank",
               "Backup preserves Health sync version and exercise history names")
    } catch { expect(false, "Valid complete backup should round trip: \(error)") }
    var invalid = original
    invalid.version = 999
    expect(rejected(invalid), "Future backup versions are rejected before mutation")
    invalid = original; invalid.foods.append(original.foods[0])
    expect(rejected(invalid), "Duplicate UUIDs are rejected before merge")
    invalid = original; invalid.days.append(original.days[0])
    expect(rejected(invalid), "Duplicate diary dates are rejected before merge")
    invalid = original; invalid.foods[0].calories = -1
    expect(rejected(invalid), "Negative imported nutrition is rejected")
    invalid = original; invalid.foods[0].proteinGrams = .infinity
    expect(rejected(invalid), "Nonfinite imported nutrition is rejected")
    invalid = original; invalid.foods[0].dayKey = "2026-10-14"
    expect(rejected(invalid), "Missing food day relationship is rejected")
    invalid = original; invalid.foods[0].timestamp = today.addingTimeInterval(86400)
    expect(rejected(invalid), "Imported food timestamp must agree with its diary day")
    invalid = original; invalid.days[0].date = today
    expect(rejected(invalid), "Diary dates must be normalized to midnight in the tracking zone")
    invalid = original; invalid.sets[0].sessionID = UUID()
    expect(rejected(invalid), "Missing set session relationship is rejected")
    invalid = original; invalid.days[0].dayKey = "2026-10-14"
    expect(rejected(invalid), "Date and tracking time zone day key must agree")
    invalid = original; invalid.profile.trackingTimeZoneID = "Unknown/Nowhere"
    expect(rejected(invalid), "Invalid diary time zones are rejected")
    invalid = original; invalid.sessions[0].endedAt = today.addingTimeInterval(-1)
    expect(rejected(invalid), "Session end cannot precede its start")
    invalid = original; invalid.sessions[0].planSnapshotJSON = "broken"
    expect(rejected(invalid), "Damaged saved workout routines are rejected")
    invalid = original; invalid.sets[0].unitRaw = "minutes"
    expect(rejected(invalid), "Unsupported workout units are rejected")
    invalid = original; invalid.sessions[0].endedAt = nil
    var second = invalid.sessions[0]; second.id = UUID(); invalid.sessions.append(second)
    expect(rejected(invalid), "Multiple unfinished imported workouts are rejected")
    do {
        _ = try BackupSnapshot.decode(Data("{broken}".utf8))
        expect(false, "Malformed JSON must fail")
    } catch { expect(true, "Malformed JSON fails without mutating the diary") }
}
