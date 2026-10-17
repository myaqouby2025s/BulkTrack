import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var key: String
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
    // Defaults allow existing local stores to migrate without changing diary measurements.
    var routineModeRaw: String = "twoOnOneOff"
    var proteinGoalGrams: Double = 0
    var calendarPlanVersion: Int = 0
    var routineEndDate: Date? = nil

    init(heightCM: Double, initialWeightKG: Double, targetWeightKG: Double, birthDate: Date,
         equation: RestingEquation, routineAnchor: Date, trackingTimeZoneID: String) {
        key = "primary"
        self.heightCM = heightCM
        self.initialWeightKG = initialWeightKG
        self.targetWeightKG = targetWeightKG
        self.birthDate = birthDate
        restingEquationRaw = equation.rawValue
        manualRestingKcal = 1700
        plannedActiveKcal = 350
        surplusKcal = 250
        proteinGramsPerKG = 1.8
        waterGoalML = 2500
        creatineGoalGrams = 5
        sleepGoalHours = 8
        self.routineAnchor = routineAnchor
        self.trackingTimeZoneID = trackingTimeZoneID
    }

    var trackingCalendar: TrackingCalendar { TrackingCalendar(timeZoneID: trackingTimeZoneID) }
    var routineMode: RoutineMode { RoutineMode(rawValue: routineModeRaw) ?? .twoOnOneOff }

    func calorieInput(weightKG: Double, now: Date) -> CalorieInput {
        let age = trackingCalendar.calendar.dateComponents([.year], from: birthDate, to: now).year ?? 30
        return CalorieInput(weightKG: weightKG, heightCM: heightCM, ageYears: age,
                            equation: RestingEquation(rawValue: restingEquationRaw) ?? .manual,
                            manualRestingKcal: manualRestingKcal, plannedActiveKcal: plannedActiveKcal,
                            surplusKcal: surplusKcal, targetWeightKG: targetWeightKG,
                            proteinGramsPerKG: proteinGramsPerKG,
                            proteinGoalGrams: proteinGoalGrams > 0 ? proteinGoalGrams : nil)
    }
}

@Model
final class DailyLog {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var waterML: Double
    var creatineGrams: Double
    var gymAttended: Bool
    @Relationship(deleteRule: .cascade, inverse: \FoodEntry.day)
    var foods: [FoodEntry]

    init(date: Date, calendar: TrackingCalendar) {
        dayKey = calendar.key(for: date)
        self.date = calendar.start(of: date)
        waterML = 0
        creatineGrams = 0
        gymAttended = false
        foods = []
    }

    var calories: Double { foods.reduce(0) { $0 + $1.calories } }
    var protein: Double { foods.reduce(0) { $0 + ($1.proteinGrams ?? 0) } }
    var carbs: Double { foods.reduce(0) { $0 + ($1.carbGrams ?? 0) } }
    var fat: Double { foods.reduce(0) { $0 + ($1.fatGrams ?? 0) } }
    var entriesMissingMacros: Int { foods.filter { !$0.hasMacros }.count }
}

@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var name: String
    var timestamp: Date
    var calories: Double
    var proteinGrams: Double?
    var carbGrams: Double?
    var fatGrams: Double?
    var isFavorite: Bool = false
    var day: DailyLog?

    init(name: String, timestamp: Date, calories: Double, proteinGrams: Double?,
         carbGrams: Double?, fatGrams: Double?) {
        id = UUID()
        self.name = name
        self.timestamp = timestamp
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
    }

    var hasMacros: Bool { proteinGrams != nil && carbGrams != nil && fatGrams != nil }
}

@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kilograms: Double
    var healthExportedAt: Date?
    var healthSyncVersion: Int = 1

    init(date: Date, kilograms: Double) {
        id = UUID()
        self.date = date
        self.kilograms = kilograms
    }
}

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var date: Date
    var exerciseID: String
    var kilograms: Double
    var reps: Int
    var unitRaw: String = "reps"
    var sessionID: UUID? = nil
    var exerciseName: String = ""

    init(date: Date, exerciseID: String, kilograms: Double, reps: Int) {
        id = UUID()
        self.date = date
        self.exerciseID = exerciseID
        self.kilograms = kilograms
        self.reps = reps
    }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var workoutRaw: String
    var dayKey: String
    var restEndsAt: Date? = nil
    var planSnapshotJSON: String = ""

    init(startedAt: Date, workout: RoutineDay, dayKey: String) {
        id = UUID()
        self.startedAt = startedAt
        workoutRaw = workout.rawValue
        self.dayKey = dayKey
    }
}

@Model
final class WorkoutScheduleOverride {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var phaseRaw: String

    init(date: Date, phase: RoutineDay, calendar: TrackingCalendar) {
        self.date = calendar.start(of: date)
        dayKey = calendar.key(for: date)
        phaseRaw = phase.rawValue
    }
}

@Model
final class TrainingExercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var plannedSets: Int
    var repGoal: String
    var workoutRaw: String
    var addedAt: Date
    var isCalendarImported: Bool = false
    var sortOrder: Int = 0

    init(name: String, plannedSets: Int, repGoal: String, workout: RoutineDay) {
        id = UUID()
        self.name = name
        self.plannedSets = plannedSets
        self.repGoal = repGoal
        workoutRaw = workout.rawValue
        addedAt = Date()
    }

    var plan: PlannedExercise {
        PlannedExercise(id: id.uuidString, name: name, sets: plannedSets, reps: repGoal)
    }
}
