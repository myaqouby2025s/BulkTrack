import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAILED: \(message)") }
}
func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.0001 }
func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

let tracking = TrackingCalendar(timeZoneID: "America/New_York")
let spring = date("2026-03-08T12:00:00Z")
let autumn = date("2026-11-01T12:00:00Z")
expect(close(tracking.interval(for: spring).duration, 23 * 3600), "Spring day is 23 hours")
expect(close(tracking.interval(for: autumn).duration, 25 * 3600), "Fall day is 25 hours")
expect(tracking.key(for: date("2026-10-10T03:59:59Z")) == "2026-10-09", "Before local midnight")
expect(tracking.key(for: date("2026-10-10T04:00:00Z")) == "2026-10-10", "At local midnight")
expect(tracking.days(endingOn: spring, count: 3).map(tracking.key) == ["2026-03-06", "2026-03-07", "2026-03-08"], "Day arithmetic crosses DST")
expect(close(tracking.elapsedFraction(at: date("2026-03-08T16:30:00Z")), 0.5), "Elapsed fraction uses actual 23-hour day")

var input = CalorieInput(weightKG: 70, heightCM: 175, ageYears: 25, equation: .male,
                         manualRestingKcal: 1700, plannedActiveKcal: 350, surplusKcal: 250,
                         targetWeightKG: 80, proteinGramsPerKG: 1.8)
let fallback = CalorieEngine.plan(input: input, energy: EnergyReading(), elapsedFraction: 0)
expect(close(fallback.restingKcal, 1673.75), "Mifflin equation")
expect(close(fallback.targetKcal, 2273.75), "Full-day target at midnight")
expect(close(fallback.proteinGrams, 126), "Protein follows current weight")
expect(close(fallback.targetKcal, 4 * fallback.proteinGrams + 4 * fallback.carbGrams + 9 * fallback.fatGrams), "Macro energy balances target")
let partial = CalorieEngine.plan(input: input, energy: EnergyReading(activeKcal: 100, basalKcal: 200), elapsedFraction: 0.5)
expect(close(partial.targetKcal, fallback.targetKcal), "Sparse data does not collapse target")
let workout = CalorieEngine.plan(input: input, energy: EnergyReading(activeKcal: 800, basalKcal: 836.875), elapsedFraction: 0.5)
expect(close(workout.activeKcal, 800), "Recorded activity replaces allowance")
expect(close(workout.targetKcal, 2723.75), "Active calories not counted twice")
let highRest = CalorieEngine.plan(input: input, energy: EnergyReading(activeKcal: 800, basalKcal: 2000), elapsedFraction: 1)
expect(close(highRest.targetKcal, 3050), "Recorded basal above baseline is respected")
input.weightKG = 80
expect(CalorieEngine.plan(input: input, energy: EnergyReading(), elapsedFraction: 1).surplusKcal == 0, "Stop surplus when target reached")
input.equation = .manual
expect(CalorieEngine.plan(input: input, energy: EnergyReading(), elapsedFraction: 1).restingKcal == 1700, "Manual resting override")
input.equation = .female
expect(close(CalorieEngine.plan(input: input, energy: EnergyReading(), elapsedFraction: 1).restingKcal, 1607.75), "Alternative equation")
expect(EnergyReading(activeKcal: nil, basalKcal: 1700).recordedTotal == nil, "Missing active isn't zero")
expect(EnergyReading(activeKcal: 0, basalKcal: 1700).recordedTotal == 1700, "Recorded zero is a value")

let anchor = tracking.start(of: date("2026-03-07T12:00:00Z"))
func day(_ index: Int) -> Date { tracking.adding(days: index, to: anchor) }
func attendance(_ indices: [Int]) -> Set<String> { Set(indices.map { tracking.key(for: day($0)) }) }
expect(Routine.phase(on: day(0), anchor: anchor, calendar: tracking) == .trainingA, "Anchor is A")
expect(Routine.phase(on: day(1), anchor: anchor, calendar: tracking) == .trainingB, "B through DST")
expect(Routine.phase(on: day(2), anchor: anchor, calendar: tracking) == .rest, "Third day rest")
expect(Routine.phase(on: day(-1), anchor: anchor, calendar: tracking) == .beforeStart, "No routine before anchor")
expect(Routine.streak(today: day(2), anchor: anchor, attended: attendance([0, 1]), calendar: tracking) == 2, "Rest preserves streak")
expect(Routine.streak(today: day(3), anchor: anchor, attended: attendance([0, 1]), calendar: tracking) == 2, "Today remains pending")
expect(Routine.streak(today: day(4), anchor: anchor, attended: attendance([0, 1]), calendar: tracking) == 0, "Missed yesterday breaks streak")
expect(Routine.streak(today: day(3), anchor: anchor, attended: attendance([0, 1, 2, 3]), calendar: tracking) == 3, "Extra rest-day workout does not inflate streak")
expect(Routine.streak(today: day(4), anchor: anchor, attended: attendance([0, 1, 4]), calendar: tracking) == 1, "New streak starts after missed session")

let t = date("2026-10-09T00:00:00Z")
func interval(_ a: Double, _ b: Double) -> DateInterval {
    DateInterval(start: t.addingTimeInterval(a * 3600), end: t.addingTimeInterval(b * 3600))
}
expect(SleepIntervals.total([], within: interval(0, 24)) == nil, "No sleep is unknown, not zero")
expect(SleepIntervals.total([interval(0, 8), interval(1, 4), interval(3, 7)], within: interval(0, 24)) == 8 * 3600, "Overlaps merged across sources")
expect(SleepIntervals.total([interval(-3, 3), interval(3, 5), interval(6, 10)], within: interval(0, 8)) == 7 * 3600, "Clipping, adjacency and awake gap")
expect(SleepIntervals.total([interval(10, 12)], within: interval(0, 8)) == nil, "Outside sleep ignored")
let window = tracking.sleepWindow(endingOn: date("2026-03-08T16:00:00Z"), now: date("2026-03-08T18:00:00Z"))!
expect(window.duration == 23 * 3600, "Sleep noon-to-noon window respects DST")
let liveWindow = tracking.sleepWindow(endingOn: date("2026-10-09T13:00:00Z"), now: date("2026-10-09T13:00:00Z"))!
expect(liveWindow.end == date("2026-10-09T13:00:00Z"), "Morning sleep query stops at now")

expect(close(USUnits.kilograms(USUnits.pounds(70)), 70), "Weight conversion round trip")
expect(close(USUnits.pounds(USUnits.kilograms(118)), 118), "Pounds entry round trip")
expect(close(USUnits.milliliters(8), 236.5882365), "Eight US fluid ounces")
expect(close(USUnits.fluidOunces(USUnits.milliliters(80)), 80), "Hydration round trip")
expect(close(USUnits.centimeters(feet: 5, inches: 8), 172.72), "Feet and inches entry")
expect(USUnits.heightParts(182.87).feet == 6 && USUnits.heightParts(182.87).inches == 0, "Height rounding carries into feet")

let monday = tracking.start(of: date("2026-10-12T12:00:00Z"))
func weekday(_ offset: Int) -> Date { tracking.adding(days: offset, to: monday) }
func weeklyPhase(_ offset: Int) -> RoutineDay {
    Routine.phase(on: weekday(offset), anchor: monday, calendar: tracking, mode: .threeDayFullBody)
}
expect(weeklyPhase(0) == .trainingA, "Weekly Monday A")
expect(weeklyPhase(1) == .rest, "Weekly Tuesday rest")
expect(weeklyPhase(2) == .trainingB, "Weekly Wednesday B")
expect(weeklyPhase(4) == .trainingA, "Weekly Friday A")
expect(weeklyPhase(7) == .trainingB, "Next Monday B")
expect(weeklyPhase(9) == .trainingA && weeklyPhase(11) == .trainingB, "Following week alternates B A B")
let weeklyAttendance = Set([0, 2, 4].map { tracking.key(for: weekday($0)) })
expect(Routine.streak(today: weekday(6), anchor: monday, attended: weeklyAttendance,
                      calendar: tracking, mode: .threeDayFullBody) == 3, "Weekend rest preserves weekly streak")
expect(Routine.streak(today: weekday(7), anchor: monday, attended: weeklyAttendance,
                      calendar: tracking, mode: .threeDayFullBody) == 3, "Pending Monday preserves weekly streak")
expect(Routine.streak(today: weekday(8), anchor: monday, attended: weeklyAttendance,
                      calendar: tracking, mode: .threeDayFullBody) == 0, "Missed Monday breaks weekly streak")
let nextTraining = Routine.nextTraining(onOrAfter: weekday(5), anchor: monday, calendar: tracking, mode: .threeDayFullBody)
expect(nextTraining.date == weekday(7) && nextTraining.phase == .trainingB, "Next workout skips weekend")
let wedAnchor = weekday(2)
expect(Routine.phase(on: weekday(2), anchor: wedAnchor, calendar: tracking, mode: .threeDayFullBody) == .trainingA,
       "Starting midweek begins with A")
expect(Routine.phase(on: weekday(4), anchor: wedAnchor, calendar: tracking, mode: .threeDayFullBody) == .trainingB,
       "Midweek plan alternates")

let averageDate = date("2026-10-14T20:00:00Z")
let measurements = [
    WeightPoint(date: date("2026-10-12T12:00:00Z"), kilograms: 50),
    WeightPoint(date: date("2026-10-12T13:00:00Z"), kilograms: 52),
    WeightPoint(date: date("2026-10-13T12:00:00Z"), kilograms: 53),
    WeightPoint(date: date("2026-10-01T12:00:00Z"), kilograms: 100),
    WeightPoint(date: date("2026-10-15T12:00:00Z"), kilograms: 100)
]
let average = WeightTrend.average(points: measurements, endingOn: averageDate, calendar: tracking)!
expect(close(average.averageKG, 52), "Daily averages avoid overweighting repeated weigh-ins")
expect(average.measuredDays == 2, "Weekly coverage counts days, not samples")
expect(WeightTrend.average(points: [], endingOn: averageDate, calendar: tracking) == nil, "Missing weekly average stays unknown")
input.proteinGoalGrams = 120
expect(CalorieEngine.plan(input: input, energy: EnergyReading(), elapsedFraction: 1).proteinGrams == 120,
       "Explicit daily protein overrides weight-based estimate")


let calendarStart = CalendarFitnessPlan.firstWorkout(calendar: tracking)
let calendarEnd = CalendarFitnessPlan.lastWorkout(calendar: tracking)
expect(tracking.key(for: calendarStart) == "2026-10-16", "Calendar plan begins on the actual Friday")
expect(Routine.phase(on: calendarStart, anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd) == .trainingA, "First calendar workout is A")
expect(Routine.phase(on: tracking.adding(days: 3, to: calendarStart), anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd) == .trainingB, "Actual following Monday is B")
expect(Routine.phase(on: tracking.adding(days: 1, to: calendarEnd), anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd) == .planComplete, "No fabricated workouts beyond calendar end")
expect(CalendarFitnessPlan.isFirstWeek(on: tracking.adding(days: 6, to: calendarStart), calendar: tracking), "First-week two-set guidance includes day six")
expect(!CalendarFitnessPlan.isFirstWeek(on: tracking.adding(days: 7, to: calendarStart), calendar: tracking), "Normal volume begins after first week")
let tueMeals = CalendarFitnessPlan.meals(on: date("2026-10-20T12:00:00Z"), calendar: tracking)
expect(tueMeals.first(where: { $0.id == "lunch" })!.hour == 14, "Tuesday lunch follows classes")
expect(tueMeals.contains(where: { $0.id == "pre-class" && $0.optional }), "Tuesday pre-class snack is optional")
let friMeals = CalendarFitnessPlan.meals(on: calendarStart, calendar: tracking)
expect(friMeals.first(where: { $0.id == "lunch" })!.hour == 12 && friMeals.count == 5, "Friday has noon lunch and five slots")
expect(CalendarFitnessPlan.exercises(for: .trainingA).last!.isTimed, "Plank is logged in seconds")
expect(CalendarFitnessPlan.exercises(for: .trainingB).first!.name == "Goblet squat", "Workout B matches calendar, not older chat")

let usLocale = Locale(identifier: "en_US")
expect(NumericInput.value("1,700", locale: usLocale) == 1700, "Formatted resting Calories accepted")
expect(NumericInput.value(" 1,700.5 ", locale: usLocale) == 1700.5, "Grouped decimal accepted")
expect(NumericInput.value("1700", locale: usLocale) == 1700, "Ungrouped numeric entry accepted")
expect(NumericInput.value("1,70", locale: usLocale) == nil, "Malformed grouping rejected")
expect(NumericInput.value("1,,700", locale: usLocale) == nil, "Repeated grouping rejected")
expect(NumericInput.value("17.5.2", locale: usLocale) == nil, "Repeated decimal rejected")
expect(NumericInput.value("1700abc", locale: usLocale) == nil, "Trailing text rejected")
expect(NumericInput.value("NaN", locale: usLocale) == nil, "Nonfinite input rejected")
expect(NumericInput.value("1.700,5", locale: Locale(identifier: "de_DE")) == 1700.5, "Locale decimal input accepted")
expect(NumericInput.value("", locale: usLocale) == nil, "Empty field remains unknown")
input.equation = .male
input.weightKG = 70
expect(close(CalorieEngine.restingCalories(for: input), 1673.75), "Preview shares the calorie engine's resting calculation")
input.equation = .manual
input.manualRestingKcal = 1750
expect(CalorieEngine.restingCalories(for: input) == 1750, "Manual resting preview uses the saved number")

// Individual plan changes and session timers must survive midnight, DST and relaunch.
let movedFriday = tracking.adding(days: 1, to: calendarStart)
let movedPlan: [String: RoutineDay] = [tracking.key(for: calendarStart): .rest, tracking.key(for: movedFriday): .trainingA]
expect(TrainingSchedule.phase(on: calendarStart, anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: movedPlan) == .rest, "Moving a workout clears its original planned day")
expect(TrainingSchedule.phase(on: movedFriday, anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: movedPlan) == .trainingA, "A day override can train on an ordinary recovery day")
expect(TrainingSchedule.nextTraining(onOrAfter: calendarStart, anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: movedPlan).date == movedFriday, "Next workout follows the moved plan")
expect(TrainingSchedule.streak(today: tracking.adding(days: 2, to: calendarStart), anchor: calendarStart, attended: [tracking.key(for: movedFriday)], calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: movedPlan) == 1, "Moved sessions count once in the streak")
expect(TrainingSchedule.streak(today: movedFriday, anchor: calendarStart, attended: [], calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: movedPlan) == 0, "Today's moved workout remains pending")
expect(TrainingSchedule.streak(today: tracking.adding(days: 2, to: calendarStart), anchor: calendarStart, attended: [tracking.key(for: calendarStart)], calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: movedPlan) == 0, "Extra attendance does not replace the missed moved session")
let afterPlan = tracking.adding(days: 4, to: calendarEnd)
let extendedOverride = [tracking.key(for: afterPlan): RoutineDay.trainingB]
expect(TrainingSchedule.nextTraining(onOrAfter: tracking.adding(days: 1, to: calendarEnd), anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: extendedOverride).phase == .trainingB, "Explicit sessions beyond the imported plan remain available")
expect(TrainingSchedule.nextTraining(onOrAfter: afterPlan, anchor: calendarStart, calendar: tracking, mode: .threeDayFullBody, end: calendarEnd, overrides: [:]).phase == .planComplete, "No invented next session after a finished plan")
let timerStart = date("2026-11-01T05:59:30Z")
let timerEnd = timerStart.addingTimeInterval(120)
expect(TrainingSchedule.remainingRest(until: timerEnd, now: timerStart.addingTimeInterval(31)) == 89, "Rest uses elapsed absolute time through a DST transition")
expect(TrainingSchedule.remainingRest(until: timerEnd, now: timerEnd.addingTimeInterval(50)) == 0, "Expired rest is zero after returning to app")
expect(TrainingSchedule.remainingRest(until: nil, now: timerStart) == 0, "Skipped rest has no remaining time")
expect(TrainingSchedule.remainingRest(until: timerEnd, now: timerEnd.addingTimeInterval(-0.2)) == 1, "Fractional rest rounds up to the next second")
let sessionPlan = [WorkoutExerciseSnapshot(id: "saved-exercise", name: "Plank", sets: 2, repGoal: "30–45 seconds")]
expect(WorkoutExerciseSnapshot.decode(WorkoutExerciseSnapshot.encode(sessionPlan)) == sessionPlan, "Session routine snapshot survives serialization")
expect(WorkoutExerciseSnapshot.decode("").isEmpty, "Legacy sessions may omit a routine snapshot")
expect(sessionPlan.first!.isTimed, "Session snapshot preserves a timed exercise")
expect(sessionPlan.first!.sets == 2 && sessionPlan.first!.plan.id == "saved-exercise", "Routine snapshot preserves sets and exercise identity")

runBackupValidationChecks()

print("Passed \(checks) core checks.")
