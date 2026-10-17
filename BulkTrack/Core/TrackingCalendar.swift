import Foundation

/// A fixed tracking zone keeps existing diary dates stable when the device travels.
struct TrackingCalendar: Sendable {
    var calendar: Calendar

    init(timeZoneID: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    func start(of date: Date) -> Date { calendar.startOfDay(for: date) }

    func format(_ date: Date, style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = calendar.timeZone
        style.calendar = calendar
        return date.formatted(style)
    }

    func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    func key(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func interval(for date: Date) -> DateInterval {
        let beginning = start(of: date)
        return DateInterval(start: beginning, end: adding(days: 1, to: beginning))
    }

    func elapsedFraction(at date: Date) -> Double {
        let day = interval(for: date)
        return min(1, max(0, date.timeIntervalSince(day.start) / day.duration))
    }

    func days(endingOn date: Date, count: Int) -> [Date] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { adding(days: -$0, to: start(of: date)) }
    }

    /// Overnight recovery belongs to the day on which the noon-to-noon window ends.
    func sleepWindow(endingOn date: Date, now: Date) -> DateInterval? {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let beginning = adding(days: -1, to: noon)
        let end = min(noon, now)
        guard end > beginning else { return nil }
        return DateInterval(start: beginning, end: end)
    }
}
