import SwiftUI

struct GymCalendarView: View {
    let calendar: TrackingCalendar
    let anchor: Date
    let today: Date
    let attended: Set<String>
    var mode: RoutineMode = .twoOnOneOff
    var end: Date? = nil
    var overrides: [String: RoutineDay] = [:]
    let toggle: (Date) -> Void
    @State private var displayedMonth = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var monthStart: Date { calendar.calendar.dateInterval(of: .month, for: displayedMonth)!.start }
    private var dates: [Date] {
        let range = calendar.calendar.range(of: .day, in: .month, for: monthStart)!
        return range.map { calendar.adding(days: $0 - 1, to: monthStart) }
    }
    private var leading: Int {
        (calendar.calendar.component(.weekday, from: monthStart) - calendar.calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(calendar.format(monthStart, style: .dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                ForEach(-leading..<0, id: \.self) { _ in Color.clear.frame(height: 48) }
                ForEach(dates, id: \.self) { day in
                    dayButton(day)
                }
            }
            HStack(spacing: 16) {
                Label("Logged", systemImage: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
                Text("A / B: planned").foregroundStyle(AppTheme.secondary)
                Label("Rest", systemImage: "minus").foregroundStyle(AppTheme.secondary)
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Text("Tap any day to adjust its plan or attendance.")
                .font(.caption).foregroundStyle(AppTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { displayedMonth = today }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: displayedMonth)
    }

    private func dayButton(_ day: Date) -> some View {
        let phase = TrainingSchedule.phase(on: day, anchor: anchor, calendar: calendar, mode: mode, end: end, overrides: overrides)
        let checked = attended.contains(calendar.key(for: day))
        let isToday = calendar.key(for: day) == calendar.key(for: today)
        return Button { toggle(day) } label: {
            VStack(spacing: 3) {
                Text("\(calendar.calendar.component(.day, from: day))").font(.subheadline.monospacedDigit())
                if checked {
                    Image(systemName: "checkmark").font(.caption2.bold())
                } else {
                    Text(phase == .trainingA ? "A" : phase == .trainingB ? "B" : "−").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(checked ? Color.white : phase.isTraining ? AppTheme.ink : AppTheme.secondary)
            .background(checked ? AppTheme.hero : phase.isTraining ? AppTheme.sage : AppTheme.background,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isToday { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.accent, lineWidth: 2) }
            }
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityLabel("\(calendar.format(day, style: .dateTime.month().day())), \(phase.title), \(checked ? "gym visit logged" : "not logged")")
        .accessibilityHint("Edit schedule or attendance")
    }

    private func moveMonth(_ count: Int) {
        displayedMonth = calendar.calendar.date(byAdding: .month, value: count, to: monthStart)!
    }
}
