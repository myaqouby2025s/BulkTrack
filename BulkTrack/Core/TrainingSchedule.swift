import Foundation

/// Diary attendance is independent from the plan; edits never fabricate completed sessions.
enum TrainingSchedule {
    static func phase(on date: Date, anchor: Date, calendar: TrackingCalendar,
                      mode: RoutineMode, end: Date?, overrides: [String: RoutineDay]) -> RoutineDay {
        overrides[calendar.key(for: date)] ?? Routine.phase(on: date, anchor: anchor, calendar: calendar, mode: mode, end: end)
    }

    static func nextTraining(onOrAfter date: Date, anchor: Date, calendar: TrackingCalendar,
                             mode: RoutineMode, end: Date?, overrides: [String: RoutineDay]) -> (date: Date, phase: RoutineDay) {
        let first = calendar.start(of: date)
        // A year covers extended plans and skipped weeks without returning an invented workout.
        for offset in 0..<366 {
            let day = calendar.adding(days: offset, to: first)
            let planned = phase(on: day, anchor: anchor, calendar: calendar, mode: mode, end: end, overrides: overrides)
            if planned.isTraining { return (day, planned) }
        }
        return (date, .planComplete)
    }

    static func streak(today: Date, anchor: Date, attended: Set<String>, calendar: TrackingCalendar,
                       mode: RoutineMode, end: Date?, overrides: [String: RoutineDay]) -> Int {
        let todayStart = calendar.start(of: today)
        var date = todayStart
        let first = min(calendar.start(of: anchor), overrides.keys.compactMap { key -> Date? in
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }.min() ?? calendar.start(of: anchor))
        var count = 0
        while date >= first {
            if phase(on: date, anchor: anchor, calendar: calendar, mode: mode, end: end, overrides: overrides).isTraining {
                if attended.contains(calendar.key(for: date)) { count += 1 }
                else if date != todayStart { break }
            }
            date = calendar.adding(days: -1, to: date)
        }
        return count
    }

    static func remainingRest(until end: Date?, now: Date) -> Int {
        guard let end else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSince(now))))
    }
}

/// A workout keeps its original routine even when the reusable A/B plan is edited later.
struct WorkoutExerciseSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let sets: Int
    let repGoal: String
    var isTimed: Bool { repGoal.localizedCaseInsensitiveContains("seconds") }
    var plan: PlannedExercise { PlannedExercise(id: id, name: name, sets: sets, reps: repGoal) }

    static func encode(_ exercises: [WorkoutExerciseSnapshot]) -> String {
        guard let data = try? JSONEncoder().encode(exercises) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func decode(_ json: String) -> [WorkoutExerciseSnapshot] {
        guard let data = json.data(using: .utf8), let exercises = try? JSONDecoder().decode([WorkoutExerciseSnapshot].self, from: data) else { return [] }
        return exercises
    }
}
