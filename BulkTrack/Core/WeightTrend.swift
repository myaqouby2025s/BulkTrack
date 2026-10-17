import Foundation

struct WeightPoint {
    var date: Date
    var kilograms: Double
}

struct WeeklyWeight {
    var averageKG: Double
    var measuredDays: Int
}

enum WeightTrend {
    /// Average each day first so repeated measurements don't give that day extra influence.
    static func average(points: [WeightPoint], endingOn date: Date, calendar: TrackingCalendar) -> WeeklyWeight? {
        let days = Set(calendar.days(endingOn: date, count: 7).map { calendar.key(for: $0) })
        let groups = Dictionary(grouping: points.filter {
            $0.date <= date && days.contains(calendar.key(for: $0.date))
        }) { calendar.key(for: $0.date) }
        let daily = groups.values.map { values in values.reduce(0) { $0 + $1.kilograms } / Double(values.count) }
        guard !daily.isEmpty else { return nil }
        return WeeklyWeight(averageKG: daily.reduce(0, +) / Double(daily.count), measuredDays: daily.count)
    }
}
