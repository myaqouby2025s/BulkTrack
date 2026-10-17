import Foundation

/// Snapshot read from the user's Apple Calendar "Fitness" events on October 14, 2026.
/// This is a local plan template, not live EventKit synchronization.
struct PlannedMeal: Identifiable {
    let id: String
    let title: String
    let hour: Int
    let minute: Int
    let venue: String
    let suggestion: String
    let nutrition: String
    let optional: Bool
}

enum CalendarFitnessPlan {
    static func date(_ day: Int, month: Int = 10, calendar: TrackingCalendar) -> Date {
        calendar.calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    static func firstWorkout(calendar: TrackingCalendar) -> Date { date(16, calendar: calendar) }
    static func lastWorkout(calendar: TrackingCalendar) -> Date { date(11, month: 11, calendar: calendar) }
    static func isActive(on date: Date, calendar: TrackingCalendar) -> Bool {
        calendar.start(of: date) >= self.date(15, calendar: calendar) &&
        calendar.start(of: date) <= lastWorkout(calendar: calendar)
    }
    static func isFirstWeek(on date: Date, calendar: TrackingCalendar) -> Bool {
        let start = firstWorkout(calendar: calendar)
        return date >= start && date < calendar.adding(days: 7, to: start)
    }
    static func meals(on date: Date, calendar: TrackingCalendar) -> [PlannedMeal] {
        let weekday = calendar.calendar.component(.weekday, from: date)
        let lateLunch = weekday == 3 || weekday == 5
        var meals: [PlannedMeal] = [
            .init(id: "breakfast", title: "Breakfast", hour: 8, minute: 30,
                  venue: "Dorm · Turner or Perry backup",
                  suggestion: "Oats, milk, peanut butter, banana and Greek yogurt. Campus alternatives: an egg-and-cheese bagel or eggs and potatoes, with no pork.",
                  nutrition: "Calendar estimate: 550–650 Cal · 25–30 g protein", optional: false)
        ]
        if lateLunch {
            meals.append(.init(id: "pre-class", title: "Pre-class snack", hour: 10, minute: 15,
                               venue: "Dorm or packed",
                               suggestion: "Banana and nuts, or Greek yogurt and fruit. Use this instead of the evening snack if your daily target is met.",
                               nutrition: "Calendar estimate: 150–250 Cal", optional: true))
        }
        meals += [
            .init(id: "lunch", title: "Lunch", hour: lateLunch ? 14 : 12, minute: lateLunch ? 15 : 0,
                  venue: "Turner · Perry / West End backup",
                  suggestion: "Qdoba chicken or steak with rice and beans. Alternatives: chicken/tofu with rice, or a rice bowl with a verified pork-free protein.",
                  nutrition: "Calendar estimate: about 750 Cal · 30–40 g protein", optional: false),
            .init(id: "shake", title: "Shake or afternoon snack", hour: 16, minute: 15, venue: "Your choice",
                  suggestion: "Only if food leaves you short. Your calendar uses ¼ of the full printed Serious Mass serving, measured by grams—not ¼ scoop. Follow your tub’s label and count any milk.",
                  nutrition: "Calendar estimate: about 430 Cal / 20 g protein with 1 cup 2% milk", optional: true),
            .init(id: "dinner", title: "Dinner", hour: 19, minute: 0,
                  venue: "West End JP’s · Turner / Perry backup",
                  suggestion: "Grilled chicken or London broil with rice/potatoes and vegetables. Alternatives: chicken/salmon and sides, or pasta with a verified pork-free protein.",
                  nutrition: "Calendar estimate: 700–800 Cal · 30–40 g protein", optional: false),
            .init(id: "evening", title: "Evening snack", hour: 21, minute: 30, venue: "Dorm",
                  suggestion: "Greek yogurt and granola, peanut-butter toast, or milk and nuts. Skip if your target is already met, especially after the pre-class snack.",
                  nutrition: "Calendar estimate: 150–250 Cal", optional: true)
        ]
        return meals
    }

    static func exercises(for phase: RoutineDay) -> [PlannedExercise] {
        if phase == .trainingB {
            return [
                .init(id: "calendar-b-goblet", name: "Goblet squat", sets: 3, reps: "8–12"),
                .init(id: "calendar-b-pulldown", name: "Lat pulldown", sets: 3, reps: "8–12"),
                .init(id: "calendar-b-incline", name: "Incline dumbbell press", sets: 3, reps: "8–12"),
                .init(id: "calendar-b-curl", name: "Seated leg curl", sets: 2, reps: "10–15"),
                .init(id: "calendar-b-lateral", name: "Lateral raise", sets: 2, reps: "12–15")
            ]
        }
        return [
            .init(id: "calendar-a-press", name: "Leg press", sets: 3, reps: "8–12"),
            .init(id: "calendar-a-bench", name: "Dumbbell bench press", sets: 3, reps: "8–12"),
            .init(id: "calendar-a-row", name: "Seated cable row", sets: 3, reps: "8–12"),
            .init(id: "calendar-a-rdl", name: "Dumbbell Romanian deadlift", sets: 2, reps: "8–10"),
            .init(id: "calendar-a-plank", name: "Plank", sets: 2, reps: "30–45 seconds")
        ]
    }
}
