import Foundation
import SwiftData

@MainActor func runBackupMergeChecks() throws {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError(message) }
    }
    let schema = Schema([UserProfile.self, DailyLog.self, FoodEntry.self, WeightEntry.self,
                         WorkoutSet.self, TrainingExercise.self, WorkoutSession.self, WorkoutScheduleOverride.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let context = ModelContext(container)
    let now = Date()
    let profile = UserProfile(heightCM: 175, initialWeightKG: 70, targetWeightKG: 80,
                              birthDate: Date(timeIntervalSince1970: 946728000), equation: .male,
                              routineAnchor: now, trackingTimeZoneID: "America/New_York")
    let day = DailyLog(date: now, calendar: profile.trackingCalendar)
    let food = FoodEntry(name: "Oats", timestamp: now, calories: 400, proteinGrams: 20, carbGrams: nil, fatGrams: 0)
    food.day = day
    food.isFavorite = true
    let weight = WeightEntry(date: now, kilograms: 70)
    weight.healthSyncVersion = 3
    weight.healthExportedAt = now
    let exercise = TrainingExercise(name: "Plank", plannedSets: 2, repGoal: "30–45 sec", workout: .trainingA)
    let session = WorkoutSession(startedAt: now, workout: .trainingA, dayKey: day.dayKey)
    session.endedAt = now.addingTimeInterval(60)
    session.planSnapshotJSON = WorkoutExerciseSnapshot.encode([.init(id: exercise.id.uuidString, name: "Plank", sets: 2, repGoal: "30–45 sec")])
    let set = WorkoutSet(date: now, exerciseID: exercise.id.uuidString, kilograms: 0, reps: 40)
    set.exerciseName = "Plank"; set.unitRaw = "seconds"; set.sessionID = session.id
    let override = WorkoutScheduleOverride(date: now, phase: .trainingA, calendar: profile.trackingCalendar)
    context.insert(profile); context.insert(day); context.insert(food); context.insert(weight)
    context.insert(exercise); context.insert(session); context.insert(set); context.insert(override)
    try context.save()
    let backup = try DataBackup.capture(context: context)
    let portable = try BackupSnapshot.decode(backup.encoded())
    try DataBackup.restore(portable, context: context)
    check(weight.healthSyncVersion == 3 && weight.healthExportedAt != nil, "Unchanged round trip must preserve Health export state despite JSON date rounding")
    let other = FoodEntry(name: "Rice", timestamp: now, calories: 200, proteinGrams: nil, carbGrams: nil, fatGrams: nil)
    other.day = day; context.insert(other); try context.save()
    food.calories = 999; weight.kilograms = 71; weight.healthSyncVersion = 4
    try context.save()
    try DataBackup.restore(portable, context: context)
    check(food.calories == 400, "Restore must update an existing UUID")
    check(day.foods.count == 2 && day.foods.contains { $0.id == other.id }, "Restore must retain unrelated food and relationships")
    check(weight.kilograms == 70 && weight.healthSyncVersion == 5 && weight.healthExportedAt == nil,
          "Restored changed weights must use a new Health revision")
    try DataBackup.restore(portable, context: context)
    check(try! context.fetchCount(FetchDescriptor<DailyLog>()) == 1, "Repeat import must not duplicate days")
    check(try! context.fetchCount(FetchDescriptor<FoodEntry>()) == 2, "Repeat import must not duplicate foods")
    check(try! context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1, "Repeat import must not duplicate sessions")
    check(try! context.fetchCount(FetchDescriptor<WorkoutSet>()) == 1, "Repeat import must not duplicate sets")
    check(weight.healthSyncVersion == 5 && weight.healthExportedAt == nil, "Old Health metadata must not replace current revision")
    check(set.exerciseName == "Plank" && session.planSnapshotJSON == portable.sessions[0].planSnapshotJSON,
          "Captured exercise and session history must survive restore")
    var bad = portable; bad.foods[0].calories = -1
    do { try DataBackup.restore(bad, context: context); fatalError("Invalid nutrition should fail") } catch {}
    check(food.calories == 400 && !context.hasChanges, "Rejected import must not mutate existing data")
    var otherZone = portable; otherZone.profile.trackingTimeZoneID = "America/Detroit"
    do { try DataBackup.restore(otherZone, context: context); fatalError("Mixed diary zones should fail") } catch {}
    check(profile.trackingTimeZoneID == "America/New_York", "Mixed-zone import must leave profile unchanged")
    let active = WorkoutSession(startedAt: now, workout: .trainingB, dayKey: day.dayKey)
    context.insert(active); try context.save()
    var activeBackup = portable; activeBackup.sessions[0].endedAt = nil
    do { try DataBackup.restore(activeBackup, context: context); fatalError("Two active sessions should fail") } catch {}
    check(session.endedAt != nil && active.endedAt == nil, "Unfinished workout conflict must leave both sessions unchanged")
    let weightOnlyContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let weightOnlyContext = ModelContext(weightOnlyContainer)
    let otherProfile = UserProfile(heightCM: 175, initialWeightKG: 70, targetWeightKG: 80,
        birthDate: profile.birthDate, equation: .male, routineAnchor: now,
        trackingTimeZoneID: "America/Los_Angeles")
    let onlyWeight = WeightEntry(date: now, kilograms: 72)
    weightOnlyContext.insert(otherProfile); weightOnlyContext.insert(onlyWeight)
    try weightOnlyContext.save()
    do { try DataBackup.restore(portable, context: weightOnlyContext); fatalError("Weight-only diary zone conflict should fail") } catch {}
    check(otherProfile.trackingTimeZoneID == "America/Los_Angeles" && onlyWeight.kilograms == 72,
          "A weight-only diary must retain its time zone and measurements on conflicting import")
    check(try! weightOnlyContext.fetchCount(FetchDescriptor<WeightEntry>()) == 1
          && weightOnlyContext.fetchCount(FetchDescriptor<DailyLog>()) == 0,
          "Rejected weight-only zone import must not insert diary data")
    print("Passed \(checks) in-memory SwiftData backup merge checks.")
}
@main struct BackupIntegrationRunner {
    @MainActor static func main() throws { try runBackupMergeChecks() }
}
