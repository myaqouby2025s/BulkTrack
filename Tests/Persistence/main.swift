import Foundation
import SwiftData

// These binaries use the same module name in separate processes, just like an app update.
// They only open the explicit temporary store passed by test-persistence.sh.
private enum CheckError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

@MainActor
private enum PersistenceChecks {
    static var count = 0
    static let foodID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let weightID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let setID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    static let calendar = TrackingCalendar(timeZoneID: "America/New_York")
    static let measuredAt = Date(timeIntervalSince1970: 1_792_000_000)
    static let exportedAt = Date(timeIntervalSince1970: 1_792_000_100)

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckError.failed(message) }
        count += 1
    }

    static func run() throws {
        guard CommandLine.arguments.count == 3 else { throw CheckError.failed("Usage: checks STORE_PATH MODE") }
        let storeURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let mode = CommandLine.arguments[2]
#if LEGACY_SEED
        let schema = Schema([UserProfile.self, DailyLog.self, FoodEntry.self, WeightEntry.self,
                             WorkoutSet.self, TrainingExercise.self])
#else
        let schema = Schema([UserProfile.self, DailyLog.self, FoodEntry.self, WeightEntry.self,
                             WorkoutSet.self, TrainingExercise.self, WorkoutSession.self, WorkoutScheduleOverride.self])
#endif
        let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.autosaveEnabled = false
#if LEGACY_SEED
        try check(mode == "seed", "Legacy executable only seeds test data")
        let profile = UserProfile(heightCM: 175, initialWeightKG: 70, targetWeightKG: 80,
                                  birthDate: Date(timeIntervalSince1970: 900_000_000), equation: .manual,
                                  routineAnchor: calendar.start(of: measuredAt), trackingTimeZoneID: "America/New_York")
        profile.calendarPlanVersion = 1
        profile.proteinGoalGrams = 135
        profile.routineModeRaw = RoutineMode.threeDayFullBody.rawValue
        profile.routineEndDate = calendar.adding(days: 30, to: measuredAt)
        context.insert(profile)
        let day = DailyLog(date: measuredAt, calendar: calendar)
        day.waterML = 500
        day.creatineGrams = 5
        day.gymAttended = true
        context.insert(day)
        let food = FoodEntry(name: "Oats & milk", timestamp: measuredAt, calories: 420,
                             proteinGrams: 25, carbGrams: nil, fatGrams: nil)
        food.id = foodID
        context.insert(food)
        day.foods.append(food)
        let weight = WeightEntry(date: measuredAt, kilograms: 70)
        weight.id = weightID
        weight.healthExportedAt = exportedAt
        context.insert(weight)
        let set = WorkoutSet(date: measuredAt, exerciseID: "legacy-plank", kilograms: 0, reps: 35)
        set.id = setID
        set.unitRaw = "seconds"
        context.insert(set)
        let exercise = TrainingExercise(name: "Plank", plannedSets: 2, repGoal: "30–45 seconds", workout: .trainingA)
        exercise.isCalendarImported = true
        context.insert(exercise)
        try context.save()
        try check(try context.fetch(FetchDescriptor<FoodEntry>()).count == 1, "Legacy seed persists food")
        print("Legacy store seeded.")
#else
        if mode == "migrate" {
            let profiles = try context.fetch(FetchDescriptor<UserProfile>())
            guard let profile = profiles.first else { throw CheckError.failed("Profile survives migration") }
            try check(profiles.count == 1, "One original profile survives")
            try check(profile.initialWeightKG == 70 && profile.targetWeightKG == 80, "Measurements survive migration")
            try check(profile.proteinGoalGrams == 135 && profile.calendarPlanVersion == 1, "Personal targets and imported plan survive")
            try check(profile.trackingTimeZoneID == "America/New_York", "Diary time zone survives")
            let days = try context.fetch(FetchDescriptor<DailyLog>())
            guard let source = days.first else { throw CheckError.failed("Daily log survives") }
            try check(source.waterML == 500 && source.creatineGrams == 5 && source.gymAttended, "Daily habits survive")
            let foods = try context.fetch(FetchDescriptor<FoodEntry>())
            guard let food = foods.first else { throw CheckError.failed("Food survives") }
            try check(foods.count == 1 && food.id == foodID, "Food identity survives")
            try check(food.proteinGrams == 25 && food.carbGrams == nil && food.fatGrams == nil, "Unknown macros remain unknown")
            try check(!food.isFavorite, "Favorite default migrates false")
            try check(food.day?.dayKey == source.dayKey && source.foods.count == 1, "Original inverse relationship survives")
            let weights = try context.fetch(FetchDescriptor<WeightEntry>())
            guard let weight = weights.first else { throw CheckError.failed("Weight survives") }
            try check(weights.count == 1 && weight.id == weightID && weight.kilograms == 70, "Weight identity and value survive")
            try check(weight.healthExportedAt == exportedAt && weight.healthSyncVersion == 1, "Health export metadata survives with sync version 1")
            let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            guard let set = sets.first else { throw CheckError.failed("Workout set survives") }
            try check(set.id == setID && set.reps == 35 && set.unitRaw == "seconds", "Timed set identity and duration survive")
            try check(set.sessionID == nil && set.exerciseName.isEmpty, "Legacy set migration defaults are safe")
            try check(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty, "Migration does not fabricate sessions")
            try check(try context.fetch(FetchDescriptor<WorkoutScheduleOverride>()).isEmpty, "Migration does not fabricate schedule overrides")
            let exercises = try context.fetch(FetchDescriptor<TrainingExercise>())
            try check(exercises.count == 1 && exercises[0].name == "Plank" && exercises[0].isCalendarImported, "Existing exercise plan survives")
            try check(exercises[0].sortOrder == 0, "Exercise ordering defaults migrate safely")

            let destination = DailyLog(date: calendar.adding(days: -1, to: measuredAt), calendar: calendar)
            context.insert(destination)
            food.day = destination
            food.timestamp = calendar.adding(days: -1, to: food.timestamp)
            food.name = "Edited oats"
            food.calories = 630
            food.proteinGrams = 37.5
            food.isFavorite = true
            weight.kilograms = 71
            weight.healthSyncVersion += 1
            weight.healthExportedAt = nil
            let session = WorkoutSession(startedAt: measuredAt, workout: .trainingA, dayKey: source.dayKey)
            session.restEndsAt = measuredAt.addingTimeInterval(120)
            context.insert(session)
            set.sessionID = session.id
            set.exerciseName = "Plank"
            let change = WorkoutScheduleOverride(date: measuredAt, phase: .rest, calendar: calendar)
            context.insert(change)
            try context.save()
            try check(source.foods.isEmpty, "Moving food removes it from its old day")
            try check(destination.foods.count == 1 && destination.foods[0].id == foodID, "Moving food adds once to the correct day")
            try check(try context.fetch(FetchDescriptor<FoodEntry>()).count == 1, "Moving food does not duplicate or delete it")
            // Regression: deleting the old cascading parent must not delete the moved food.
            context.delete(source)
            try context.save()
            try check(try context.fetch(FetchDescriptor<FoodEntry>()).count == 1, "Moved food survives deletion of its former day")
        } else if mode == "reopen" {
            let foods = try context.fetch(FetchDescriptor<FoodEntry>())
            guard let food = foods.first else { throw CheckError.failed("Moved food persists on reopen") }
            try check(foods.count == 1 && food.id == foodID && food.name == "Edited oats", "Edited food and identity persist")
            try check(food.isFavorite && food.calories == 630 && food.proteinGrams == 37.5, "Favorite and edited nutrition persist")
            try check(food.carbGrams == nil && food.fatGrams == nil, "Portion change keeps unknown macros nil")
            try check(food.day?.foods.count == 1 && food.day?.dayKey == calendar.key(for: calendar.adding(days: -1, to: measuredAt)), "Food inverse persists after restart")
            let weights = try context.fetch(FetchDescriptor<WeightEntry>())
            guard let weight = weights.first else { throw CheckError.failed("Edited weight persists") }
            try check(weight.id == weightID && weight.kilograms == 71, "Weight edit retains identity")
            try check(weight.healthSyncVersion == 2 && weight.healthExportedAt == nil, "Weight edit requires export with a newer sync version")
            let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            try check(sets.count == 1 && sessions.count == 1 && sets[0].sessionID == sessions[0].id, "Session linkage persists")
            try check(sets[0].exerciseName == "Plank" && sets[0].unitRaw == "seconds", "Exercise snapshot and timed units persist")
            try check(sessions[0].restEndsAt == measuredAt.addingTimeInterval(120), "Rest timer deadline persists")
            let overrides = try context.fetch(FetchDescriptor<WorkoutScheduleOverride>())
            try check(overrides.count == 1 && overrides[0].phaseRaw == RoutineDay.rest.rawValue, "Schedule override persists")
        } else {
            throw CheckError.failed("Unknown mode: \(mode)")
        }
        print("\(count) persistence checks passed (\(mode)).")
#endif
    }
}

do {
    try MainActor.assumeIsolated { try PersistenceChecks.run() }
} catch {
    fputs("Persistence checks failed: \(error)\n", stderr)
    exit(1)
}
