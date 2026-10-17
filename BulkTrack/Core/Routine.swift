import Foundation

enum RoutineMode: String, CaseIterable, Identifiable {
    case twoOnOneOff
    case threeDayFullBody
    var id: String { rawValue }
    var title: String { self == .threeDayFullBody ? "Mon / Wed / Fri" : "Two on, one off" }
    var detail: String {
        self == .threeDayFullBody ? "Three days a week · alternate A and B" : "A → B → Rest · repeat"
    }
}

enum RoutineDay: String {
    case trainingA = "Training A", trainingB = "Training B", rest = "Rest", beforeStart = "Before routine", planComplete = "Plan complete"
    var isTraining: Bool { self == .trainingA || self == .trainingB }
    var title: String {
        switch self {
        case .trainingA: "Workout A"
        case .trainingB: "Workout B"
        case .rest: "Recovery day"
        case .beforeStart: "Before your plan"
        case .planComplete: "Plan complete"
        }
    }
}

enum Routine {
    static func phase(on date: Date, anchor: Date, calendar: TrackingCalendar,
                      mode: RoutineMode = .twoOnOneOff, end: Date? = nil) -> RoutineDay {
        if let end, calendar.start(of: date) > calendar.start(of: end) { return .planComplete }
        let offset = calendar.calendar.dateComponents([.day], from: calendar.start(of: anchor),
                                                     to: calendar.start(of: date)).day ?? 0
        guard offset >= 0 else { return .beforeStart }
        if mode == .threeDayFullBody {
            let weekdays: Set<Int> = [2, 4, 6]
            guard weekdays.contains(calendar.calendar.component(.weekday, from: date)) else { return .rest }
            let weeks = offset / 7
            var sessionCount = weeks * 3
            for index in 0...(offset % 7) {
                let day = calendar.adding(days: index, to: calendar.start(of: anchor))
                if weekdays.contains(calendar.calendar.component(.weekday, from: day)) { sessionCount += 1 }
            }
            return sessionCount % 2 == 1 ? .trainingA : .trainingB
        }
        switch offset % 3 {
        case 0: return .trainingA
        case 1: return .trainingB
        default: return .rest
        }
    }

    /// Consecutive scheduled sessions. Rest days neither add to nor break the count.
    /// An unfinished session today becomes missed only when the tracking day ends.
    static func streak(today: Date, anchor: Date, attended: Set<String>, calendar: TrackingCalendar,
                       mode: RoutineMode = .twoOnOneOff, end: Date? = nil) -> Int {
        var day = calendar.start(of: today)
        let first = calendar.start(of: anchor)
        var count = 0
        while day >= first {
            if phase(on: day, anchor: first, calendar: calendar, mode: mode, end: end).isTraining {
                if attended.contains(calendar.key(for: day)) {
                    count += 1
                } else if day != calendar.start(of: today) {
                    break
                }
            }
            day = calendar.adding(days: -1, to: day)
        }
        return count
    }

    static func nextTraining(onOrAfter date: Date, anchor: Date, calendar: TrackingCalendar,
                             mode: RoutineMode, end: Date? = nil) -> (date: Date, phase: RoutineDay) {
        if let end, calendar.start(of: date) > calendar.start(of: end) { return (date, .planComplete) }
        for offset in 0..<10 {
            let day = calendar.adding(days: offset, to: calendar.start(of: max(date, anchor)))
            let phase = phase(on: day, anchor: anchor, calendar: calendar, mode: mode, end: end)
            if phase.isTraining { return (day, phase) }
        }
        return (date, end == nil ? .trainingA : .planComplete)
    }
}
