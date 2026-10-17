import Foundation

/// Portable local diary data. HealthKit readings remain in Apple Health and are read again.
struct BackupSnapshot: Codable {
    static let currentVersion = 1
    static let maximumBytes = 30 * 1024 * 1024
    var format = "BulkTrackBackup"
    var version = currentVersion
    var createdAt: Date
    var profile: Profile
    var days: [Day]
    var foods: [Food]
    var weights: [Weight]
    var exercises: [Exercise]
    var sets: [SetRecord]
    var sessions: [Session]
    var schedule: [Schedule]

    struct Profile: Codable {
        var key: String
        var heightCM: Double
        var initialWeightKG: Double
        var targetWeightKG: Double
        var birthDate: Date
        var restingEquationRaw: String
        var manualRestingKcal: Double
        var plannedActiveKcal: Double
        var surplusKcal: Double
        var proteinGramsPerKG: Double
        var waterGoalML: Double
        var creatineGoalGrams: Double
        var sleepGoalHours: Double
        var routineAnchor: Date
        var trackingTimeZoneID: String
        var routineModeRaw: String
        var proteinGoalGrams: Double
        var calendarPlanVersion: Int
        var routineEndDate: Date?
    }
    struct Day: Codable {
        var dayKey: String
        var date: Date
        var waterML: Double
        var creatineGrams: Double
        var gymAttended: Bool
    }
    struct Food: Codable {
        var id: UUID
        var name: String
        var timestamp: Date
        var calories: Double
        var proteinGrams: Double?
        var carbGrams: Double?
        var fatGrams: Double?
        var isFavorite: Bool
        var dayKey: String?
    }
    struct Weight: Codable {
        var id: UUID
        var date: Date
        var kilograms: Double
        var healthExportedAt: Date?
        var healthSyncVersion: Int
    }
    struct Exercise: Codable {
        var id: UUID
        var name: String
        var plannedSets: Int
        var repGoal: String
        var workoutRaw: String
        var addedAt: Date
        var isCalendarImported: Bool
        var sortOrder: Int? = nil
    }
    struct SetRecord: Codable {
        var id: UUID
        var date: Date
        var exerciseID: String
        var exerciseName: String
        var kilograms: Double
        var reps: Int
        var unitRaw: String
        var sessionID: UUID?
    }
    struct Session: Codable {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var workoutRaw: String
        var dayKey: String
        var restEndsAt: Date?
        var planSnapshotJSON: String
    }
    struct Schedule: Codable {
        var dayKey: String
        var date: Date
        var phaseRaw: String
    }

    var recordCount: Int {
        days.count + foods.count + weights.count + exercises.count + sets.count + sessions.count + schedule.count
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw BackupError.invalid("This backup is larger than 30 MB.") }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw BackupError.invalid("Choose a BulkTrack JSON backup smaller than 30 MB.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot: Self
        do { snapshot = try decoder.decode(Self.self, from: data) }
        catch { throw BackupError.invalid("This file is not a complete BulkTrack JSON backup, or its format is damaged.") }
        try snapshot.validate()
        return snapshot
    }

    func validate() throws {
        guard format == "BulkTrackBackup", version == Self.currentVersion else {
            throw BackupError.invalid("This backup format is unsupported. Use the app version that created it, or a newer compatible version.")
        }
        guard recordCount <= 150_000 else { throw BackupError.invalid("This backup contains too many records to import safely.") }
        try require(validDate(createdAt), "The backup date is invalid.")
        let p = profile
        try require(p.key == "primary" && TimeZone(identifier: p.trackingTimeZoneID) != nil,
                    "The backup profile or diary time zone is invalid.")
        try require(inRange(p.heightCM, 120...230) && inRange(p.initialWeightKG, 20...400)
                    && inRange(p.targetWeightKG, 20...400), "The backup contains invalid profile measurements.")
        try require(validDate(p.birthDate) && validDate(p.routineAnchor)
                    && (p.routineEndDate.map(validDate) ?? true), "The backup contains an invalid profile date.")
        try require(RestingEquation(rawValue: p.restingEquationRaw) != nil
                    && RoutineMode(rawValue: p.routineModeRaw) != nil,
                    "The backup contains an unsupported calorie formula or workout schedule.")
        try require(inRange(p.manualRestingKcal, 0...10_000) && inRange(p.plannedActiveKcal, 0...20_000)
                    && inRange(p.surplusKcal, 0...5_000) && inRange(p.proteinGramsPerKG, 0...10)
                    && inRange(p.proteinGoalGrams, 0...1_000) && inRange(p.waterGoalML, 0...30_000)
                    && inRange(p.creatineGoalGrams, 0...100) && inRange(p.sleepGoalHours, 0...24)
                    && (-1...10_000).contains(p.calendarPlanVersion), "The backup contains an invalid daily goal.")
        let calendar = TrackingCalendar(timeZoneID: p.trackingTimeZoneID)
        try unique(days.map(\.dayKey), "diary days")
        try unique(foods.map(\.id), "food entries")
        try unique(weights.map(\.id), "weight entries")
        try unique(exercises.map(\.id), "exercises")
        try unique(sets.map(\.id), "workout sets")
        try unique(sessions.map(\.id), "workout sessions")
        try unique(schedule.map(\.dayKey), "schedule changes")
        let dayKeys = Set(days.map(\.dayKey))
        let sessionIDs = Set(sessions.map(\.id))
        try require(sessions.filter { $0.endedAt == nil }.count <= 1, "The backup contains more than one unfinished workout.")
        for day in days {
            try require(validDate(day.date) && day.date == calendar.start(of: day.date)
                        && day.dayKey == calendar.key(for: day.date)
                        && inRange(day.waterML, 0...100_000) && inRange(day.creatineGrams, 0...1_000),
                        "The backup contains an invalid diary day.")
        }
        for food in foods {
            try require(validName(food.name) && validDate(food.timestamp) && inRange(food.calories, 0...100_000)
                        && (food.proteinGrams.map { inRange($0, 0...10_000) } ?? true)
                        && (food.carbGrams.map { inRange($0, 0...10_000) } ?? true)
                        && (food.fatGrams.map { inRange($0, 0...10_000) } ?? true),
                        "The backup contains invalid food nutrition or a food name.")
            try require(food.dayKey.map { dayKeys.contains($0) && $0 == calendar.key(for: food.timestamp) } ?? true,
                        "A food entry refers to a diary day missing from the backup.")
        }
        for weight in weights {
            try require(validDate(weight.date) && inRange(weight.kilograms, 20...400)
                        && (weight.healthExportedAt.map(validDate) ?? true)
                        && (1...1_000_000).contains(weight.healthSyncVersion), "The backup contains an invalid weight entry.")
        }
        for exercise in exercises {
            try require(validName(exercise.name) && validName(exercise.repGoal)
                        && (1...100).contains(exercise.plannedSets) && validDate(exercise.addedAt)
                        && RoutineDay(rawValue: exercise.workoutRaw)?.isTraining == true
                        && (exercise.sortOrder.map { (0...1_000_000).contains($0) } ?? true),
                        "The backup contains an invalid exercise.")
        }
        for set in sets {
            // Old sets may keep an exercise ID after that exercise was removed.
            try require(validName(set.exerciseID) && set.exerciseName.count <= 500 && validDate(set.date) && inRange(set.kilograms, 0...2_000)
                        && (1...100_000).contains(set.reps) && ["reps", "seconds"].contains(set.unitRaw),
                        "The backup contains an invalid workout set.")
            try require(set.sessionID.map { sessionIDs.contains($0) } ?? true,
                        "A workout set refers to a session missing from the backup.")
        }
        for session in sessions {
            try require(validDate(session.startedAt) && session.dayKey == calendar.key(for: session.startedAt)
                        && RoutineDay(rawValue: session.workoutRaw)?.isTraining == true,
                        "The backup contains an invalid workout session.")
            if let end = session.endedAt {
                try require(validDate(end) && end >= session.startedAt, "A workout ends before it starts.")
            }
            try require(session.restEndsAt.map(validDate) ?? true, "A workout rest timer is invalid.")
            try require(session.planSnapshotJSON.utf8.count <= 200_000, "A saved workout routine is too large.")
            if !session.planSnapshotJSON.isEmpty {
                guard let data = session.planSnapshotJSON.data(using: .utf8),
                      let plan = try? JSONDecoder().decode([WorkoutExerciseSnapshot].self, from: data) else {
                    throw BackupError.invalid("A saved workout routine is damaged.")
                }
                try unique(plan.map(\.id), "saved workout exercises")
                try require(plan.count <= 1_000 && plan.allSatisfy {
                    validName($0.id) && validName($0.name) && validName($0.repGoal) && (1...100).contains($0.sets)
                }, "A saved workout routine contains invalid exercises.")
            }
        }
        for change in schedule {
            try require(validDate(change.date) && change.date == calendar.start(of: change.date)
                        && change.dayKey == calendar.key(for: change.date)
                        && [RoutineDay.trainingA.rawValue, RoutineDay.trainingB.rawValue, RoutineDay.rest.rawValue].contains(change.phaseRaw),
                        "The backup contains an invalid schedule change.")
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw BackupError.invalid(message) }
    }
    private func unique<T: Hashable>(_ values: [T], _ name: String) throws {
        try require(Set(values).count == values.count, "The backup contains duplicate \(name).")
    }
    private func inRange(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value)
    }
    private func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 500
    }
    private func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970)
    }
}

enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
