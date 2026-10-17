import Foundation
import SwiftData

@MainActor
enum DiaryStore {
    static func installCalendarPlan(profile: UserProfile, context: ModelContext) throws {
        guard profile.calendarPlanVersion < 1 else { return }
        try save(context: context) {
            let calendar = profile.trackingCalendar
            if profile.calendarPlanVersion == 0 {
                profile.routineModeRaw = RoutineMode.threeDayFullBody.rawValue
                profile.routineAnchor = CalendarFitnessPlan.firstWorkout(calendar: calendar)
                profile.routineEndDate = CalendarFitnessPlan.lastWorkout(calendar: calendar)
            }
            for phase in [RoutineDay.trainingA, .trainingB] {
                for planned in CalendarFitnessPlan.exercises(for: phase) {
                    let exercise = TrainingExercise(name: planned.name, plannedSets: planned.sets,
                                                    repGoal: planned.reps, workout: phase)
                    exercise.isCalendarImported = true
                    context.insert(exercise)
                }
            }
            profile.calendarPlanVersion = 1
        }
    }

    static func day(for date: Date, calendar: TrackingCalendar, context: ModelContext) throws -> DailyLog {
        let key = calendar.key(for: date)
        var request = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == key })
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first { return existing }
        let log = DailyLog(date: date, calendar: calendar)
        context.insert(log)
        return log
    }

    /// All UI writes save explicitly. A failure rolls back unsaved changes and is shown to the user.
    static func save(context: ModelContext, changes: () throws -> Void) throws {
        do {
            try changes()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
