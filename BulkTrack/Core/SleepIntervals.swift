import Foundation

enum SleepIntervals {
    /// Clip to the recovery window and take the union across sources/stages.
    /// Callers supply asleep intervals only, never in-bed or awake samples.
    static func total(_ intervals: [DateInterval], within window: DateInterval) -> TimeInterval? {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start)
            let end = min(interval.end, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        guard var merged = clipped.first else { return nil }
        var seconds = 0.0
        for interval in clipped.dropFirst() {
            if interval.start <= merged.end {
                merged = DateInterval(start: merged.start, end: max(merged.end, interval.end))
            } else {
                seconds += merged.duration
                merged = interval
            }
        }
        return seconds + merged.duration
    }
}
