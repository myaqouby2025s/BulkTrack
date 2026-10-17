import Foundation
import SwiftData

@MainActor
enum DataBackup {
    static func capture(context: ModelContext) throws -> BackupSnapshot {
        guard let p = try context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw BackupError.invalid("Create a profile before exporting your diary.")
        }
        let days = try context.fetch(FetchDescriptor<DailyLog>())
        let foods = try context.fetch(FetchDescriptor<FoodEntry>())
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let exercises = try context.fetch(FetchDescriptor<TrainingExercise>())
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let schedule = try context.fetch(FetchDescriptor<WorkoutScheduleOverride>())
        let snapshot = BackupSnapshot(createdAt: Date(), profile: .init(
            key: p.key, heightCM: p.heightCM, initialWeightKG: p.initialWeightKG, targetWeightKG: p.targetWeightKG,
            birthDate: p.birthDate, restingEquationRaw: p.restingEquationRaw, manualRestingKcal: p.manualRestingKcal,
            plannedActiveKcal: p.plannedActiveKcal, surplusKcal: p.surplusKcal, proteinGramsPerKG: p.proteinGramsPerKG,
            waterGoalML: p.waterGoalML, creatineGoalGrams: p.creatineGoalGrams, sleepGoalHours: p.sleepGoalHours,
            routineAnchor: p.routineAnchor, trackingTimeZoneID: p.trackingTimeZoneID, routineModeRaw: p.routineModeRaw,
            proteinGoalGrams: p.proteinGoalGrams, calendarPlanVersion: p.calendarPlanVersion, routineEndDate: p.routineEndDate),
            days: days.sorted { $0.dayKey < $1.dayKey }.map {
                .init(dayKey: $0.dayKey, date: $0.date, waterML: $0.waterML,
                      creatineGrams: $0.creatineGrams, gymAttended: $0.gymAttended)
            }, foods: foods.sorted { $0.timestamp < $1.timestamp }.map {
                .init(id: $0.id, name: $0.name, timestamp: $0.timestamp, calories: $0.calories,
                      proteinGrams: $0.proteinGrams, carbGrams: $0.carbGrams, fatGrams: $0.fatGrams,
                      isFavorite: $0.isFavorite, dayKey: $0.day?.dayKey)
            }, weights: weights.sorted { $0.date < $1.date }.map {
                .init(id: $0.id, date: $0.date, kilograms: $0.kilograms, healthExportedAt: $0.healthExportedAt,
                      healthSyncVersion: $0.healthSyncVersion)
            }, exercises: exercises.sorted { $0.addedAt < $1.addedAt }.map {
                .init(id: $0.id, name: $0.name, plannedSets: $0.plannedSets, repGoal: $0.repGoal,
                      workoutRaw: $0.workoutRaw, addedAt: $0.addedAt, isCalendarImported: $0.isCalendarImported, sortOrder: $0.sortOrder)
            }, sets: sets.sorted { $0.date < $1.date }.map {
                .init(id: $0.id, date: $0.date, exerciseID: $0.exerciseID, exerciseName: $0.exerciseName, kilograms: $0.kilograms,
                      reps: $0.reps, unitRaw: $0.unitRaw, sessionID: $0.sessionID)
            }, sessions: sessions.sorted { $0.startedAt < $1.startedAt }.map {
                .init(id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt,
                      workoutRaw: $0.workoutRaw, dayKey: $0.dayKey, restEndsAt: $0.restEndsAt, planSnapshotJSON: $0.planSnapshotJSON)
            }, schedule: schedule.sorted { $0.dayKey < $1.dayKey }.map {
                .init(dayKey: $0.dayKey, date: $0.date, phaseRaw: $0.phaseRaw)
            })
        try snapshot.validate()
        return snapshot
    }

    /// A single save commits the merge. Existing entries absent from the backup are retained.
    static func restore(_ snapshot: BackupSnapshot, context: ModelContext) throws {
        try snapshot.validate()
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let existingDays = try context.fetch(FetchDescriptor<DailyLog>())
        let existingFoods = try context.fetch(FetchDescriptor<FoodEntry>())
        let existingWeights = try context.fetch(FetchDescriptor<WeightEntry>())
        let existingExercises = try context.fetch(FetchDescriptor<TrainingExercise>())
        let existingSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let existingSchedule = try context.fetch(FetchDescriptor<WorkoutScheduleOverride>())
        if let current = profiles.first, current.trackingTimeZoneID != snapshot.profile.trackingTimeZoneID,
           !existingDays.isEmpty || !existingFoods.isEmpty || !existingWeights.isEmpty || !existingSets.isEmpty
            || !existingSessions.isEmpty || !existingSchedule.isEmpty {
            throw BackupError.invalid("This backup uses \(snapshot.profile.trackingTimeZoneID), while your diary uses \(current.trackingTimeZoneID). Merging different diary time zones could move entries to another day. Restore a backup from the same diary time zone.")
        }
        let replacedSessionIDs = Set(snapshot.sessions.map(\.id))
        let activeSessions = existingSessions.filter { $0.endedAt == nil && !replacedSessionIDs.contains($0.id) }.count
            + snapshot.sessions.filter { $0.endedAt == nil }.count
        guard activeSessions <= 1 else {
            throw BackupError.invalid("Finish your current workout before restoring a backup with a different unfinished workout.")
        }
        // Protect any previously pending local edits before starting this atomic merge.
        if context.hasChanges { try context.save() }
        do {
            let p = snapshot.profile
            let calendar = TrackingCalendar(timeZoneID: p.trackingTimeZoneID)
            let profile = profiles.first ?? UserProfile(heightCM: p.heightCM, initialWeightKG: p.initialWeightKG,
                targetWeightKG: p.targetWeightKG, birthDate: p.birthDate,
                equation: RestingEquation(rawValue: p.restingEquationRaw)!,
                routineAnchor: p.routineAnchor, trackingTimeZoneID: p.trackingTimeZoneID)
            if profiles.isEmpty { context.insert(profile) }
            profile.key = p.key
            profile.heightCM = p.heightCM
            profile.initialWeightKG = p.initialWeightKG
            profile.targetWeightKG = p.targetWeightKG
            profile.birthDate = p.birthDate
            profile.restingEquationRaw = p.restingEquationRaw
            profile.manualRestingKcal = p.manualRestingKcal
            profile.plannedActiveKcal = p.plannedActiveKcal
            profile.surplusKcal = p.surplusKcal
            profile.proteinGramsPerKG = p.proteinGramsPerKG
            profile.waterGoalML = p.waterGoalML
            profile.creatineGoalGrams = p.creatineGoalGrams
            profile.sleepGoalHours = p.sleepGoalHours
            profile.routineAnchor = p.routineAnchor
            profile.trackingTimeZoneID = p.trackingTimeZoneID
            profile.routineModeRaw = p.routineModeRaw
            profile.proteinGoalGrams = p.proteinGoalGrams
            profile.calendarPlanVersion = p.calendarPlanVersion
            profile.routineEndDate = p.routineEndDate

            var days = Dictionary(uniqueKeysWithValues: existingDays.map { ($0.dayKey, $0) })
            for item in snapshot.days {
                let day = days[item.dayKey] ?? DailyLog(date: item.date, calendar: calendar)
                if days[item.dayKey] == nil { context.insert(day); days[item.dayKey] = day }
                day.dayKey = item.dayKey
                day.date = item.date
                day.waterML = item.waterML
                day.creatineGrams = item.creatineGrams
                day.gymAttended = item.gymAttended
            }
            let foods = Dictionary(uniqueKeysWithValues: existingFoods.map { ($0.id, $0) })
            for item in snapshot.foods {
                let food = foods[item.id] ?? FoodEntry(name: item.name, timestamp: item.timestamp,
                    calories: item.calories, proteinGrams: item.proteinGrams, carbGrams: item.carbGrams, fatGrams: item.fatGrams)
                if foods[item.id] == nil { context.insert(food) }
                food.id = item.id
                food.name = item.name
                food.timestamp = item.timestamp
                food.calories = item.calories
                food.proteinGrams = item.proteinGrams
                food.carbGrams = item.carbGrams
                food.fatGrams = item.fatGrams
                food.isFavorite = item.isFavorite
                food.day = item.dayKey.flatMap { days[$0] }
            }
            let weights = Dictionary(uniqueKeysWithValues: existingWeights.map { ($0.id, $0) })
            for item in snapshot.weights {
                let old = weights[item.id]
                let weight = old ?? WeightEntry(date: item.date, kilograms: item.kilograms)
                // JSON stores millisecond timestamps; sub-millisecond rounding is not a changed reading.
                let changed = old.map { abs($0.date.timeIntervalSince(item.date)) > 0.001 || $0.kilograms != item.kilograms } ?? false
                let localVersion = old?.healthSyncVersion ?? 1
                let localExportedAt = old?.healthExportedAt
                let highestVersion = max(localVersion, item.healthSyncVersion)
                if old == nil { context.insert(weight) }
                weight.id = item.id
                weight.date = item.date
                weight.kilograms = item.kilograms
                // Restoring an older reading must never reuse a lower HealthKit sync version.
                weight.healthSyncVersion = changed ? highestVersion + 1 : highestVersion
                if changed {
                    weight.healthExportedAt = nil
                } else if old != nil, localVersion > item.healthSyncVersion {
                    // Keep local export state when the imported metadata is from an older revision.
                    weight.healthExportedAt = localExportedAt
                } else {
                    weight.healthExportedAt = item.healthExportedAt
                }
            }
            let exercises = Dictionary(uniqueKeysWithValues: existingExercises.map { ($0.id, $0) })
            for item in snapshot.exercises {
                let exercise = exercises[item.id] ?? TrainingExercise(name: item.name, plannedSets: item.plannedSets,
                    repGoal: item.repGoal, workout: RoutineDay(rawValue: item.workoutRaw)!)
                if exercises[item.id] == nil { context.insert(exercise) }
                exercise.id = item.id
                exercise.name = item.name
                exercise.plannedSets = item.plannedSets
                exercise.repGoal = item.repGoal
                exercise.workoutRaw = item.workoutRaw
                exercise.addedAt = item.addedAt
                exercise.isCalendarImported = item.isCalendarImported
                exercise.sortOrder = item.sortOrder ?? 0
            }
            let sessions = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
            for item in snapshot.sessions {
                let session = sessions[item.id] ?? WorkoutSession(startedAt: item.startedAt,
                    workout: RoutineDay(rawValue: item.workoutRaw)!, dayKey: item.dayKey)
                if sessions[item.id] == nil { context.insert(session) }
                session.id = item.id
                session.startedAt = item.startedAt
                session.endedAt = item.endedAt
                session.workoutRaw = item.workoutRaw
                session.dayKey = item.dayKey
                session.restEndsAt = item.restEndsAt
                session.planSnapshotJSON = item.planSnapshotJSON
            }
            let sets = Dictionary(uniqueKeysWithValues: existingSets.map { ($0.id, $0) })
            for item in snapshot.sets {
                let set = sets[item.id] ?? WorkoutSet(date: item.date, exerciseID: item.exerciseID,
                    kilograms: item.kilograms, reps: item.reps)
                if sets[item.id] == nil { context.insert(set) }
                set.id = item.id
                set.date = item.date
                set.exerciseID = item.exerciseID
                set.exerciseName = item.exerciseName
                set.kilograms = item.kilograms
                set.reps = item.reps
                set.unitRaw = item.unitRaw
                set.sessionID = item.sessionID
            }
            let schedule = Dictionary(uniqueKeysWithValues: existingSchedule.map { ($0.dayKey, $0) })
            for item in snapshot.schedule {
                let change = schedule[item.dayKey] ?? WorkoutScheduleOverride(date: item.date,
                    phase: RoutineDay(rawValue: item.phaseRaw)!, calendar: calendar)
                if schedule[item.dayKey] == nil { context.insert(change) }
                change.dayKey = item.dayKey
                change.date = item.date
                change.phaseRaw = item.phaseRaw
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
