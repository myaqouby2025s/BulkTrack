import SwiftUI
import Charts

private struct EnergyBar: Identifiable {
    let day: String
    let series: String
    let calories: Double
    var id: String { day + series }
}

struct ProgressChartsView: View {
    let weights: [WeightEntry]
    let logs: [DailyLog]
    let healthDays: [String: HealthDay]
    let calendar: TrackingCalendar
    let now: Date
    let targetWeight: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range = 30
    @State private var selectedDate: Date?

    private var recentWeights: [WeightEntry] {
        weights.filter { $0.date >= calendar.adding(days: -range, to: now) && $0.date <= now }
    }
    private var points: [WeightPoint] { weights.map { WeightPoint(date: $0.date, kilograms: $0.kilograms) } }
    private var week: WeeklyWeight? { WeightTrend.average(points: points, endingOn: now, calendar: calendar) }
    private var previousWeek: WeeklyWeight? {
        WeightTrend.average(points: points, endingOn: calendar.adding(days: -7, to: now), calendar: calendar)
    }
    private var selectedWeight: WeightEntry? {
        guard let selectedDate else { return nil }
        return recentWeights.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var chartDates: [Date] { calendar.days(endingOn: now, count: 7) }
    private var chartDays: [String] { chartDates.map { calendar.key(for: $0) } }
    private var energyBars: [EnergyBar] {
        chartDays.flatMap { key -> [EnergyBar] in
            var bars: [EnergyBar] = []
            if let log = logs.first(where: { $0.dayKey == key }), !log.foods.isEmpty {
                bars.append(.init(day: key, series: "Eaten", calories: log.calories))
            }
            if let total = healthDays[key]?.energy.recordedTotal {
                bars.append(.init(day: key, series: "Burned", calories: total))
            }
            return bars
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            weeklyAverageCard
            weightChartCard
            energyChartCard
        }
    }

    private var weeklyAverageCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    IconBadge(symbol: "chart.line.uptrend.xyaxis", color: AppTheme.accent, background: AppTheme.sage)
                    CardHeading(title: "Weekly average", subtitle: "Your last seven days")
                }
                if let week {
                    Text(USUnits.weight(week.averageKG)).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("\(week.measuredDays) weigh-in \(week.measuredDays == 1 ? "day" : "days") this week")
                        .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    if let previousWeek, previousWeek.measuredDays >= 3, week.measuredDays >= 3 {
                        let delta = USUnits.pounds(week.averageKG - previousWeek.averageKG)
                        Label("\(delta >= 0 ? "+" : "")\(USUnits.number(delta, digits: 2)) lb compared with the prior seven days",
                              systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.subheadline.weight(.medium)).foregroundStyle(delta >= 0 ? AppTheme.accent : AppTheme.peachInk)
                    } else {
                        Text("Log at least three mornings in each week for a useful comparison.")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                } else {
                    Text("Your trend starts with a weigh-in.").font(.subheadline).foregroundStyle(AppTheme.secondary)
                }
                Text("Look for the trend over several weeks. Daily weight can fluctuate.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private var weightChartCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                CardHeading(title: "Weight history", subtitle: "Measured weight · lb")
                Picker("Weight chart range", selection: $range) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }.pickerStyle(.segmented)
                if let selectedWeight {
                    Text("\(calendar.format(selectedWeight.date, style: .dateTime.month(.abbreviated).day())) · \(USUnits.weight(selectedWeight.kilograms))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                }
                if recentWeights.isEmpty {
                    emptyState("scalemass", text: "Add a weigh-in to see your progress.")
                } else {
                    Chart {
                        ForEach(recentWeights) { entry in
                            LineMark(x: .value("Date", entry.date), y: .value("Pounds", USUnits.pounds(entry.kilograms)))
                                .foregroundStyle(AppTheme.accent).lineStyle(StrokeStyle(lineWidth: 3))
                            PointMark(x: .value("Date", entry.date), y: .value("Pounds", USUnits.pounds(entry.kilograms)))
                                .foregroundStyle(AppTheme.accent).symbolSize(35)
                                .accessibilityLabel(calendar.format(entry.date, style: .dateTime.month().day()))
                                .accessibilityValue(USUnits.weight(entry.kilograms))
                        }
                        RuleMark(y: .value("Goal", USUnits.pounds(targetWeight)))
                            .lineStyle(StrokeStyle(dash: [5, 5])).foregroundStyle(AppTheme.secondary.opacity(0.65))
                    }
                    .chartXScale(domain: calendar.adding(days: -range, to: now)...now)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel("lb")
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 220)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: range)
                    .onChange(of: range) { _, _ in selectedDate = nil }
                    Text("Touch the chart to inspect a weigh-in. Dashed line: your \(USUnits.weight(targetWeight)) goal.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }
        }
    }

    private var energyChartCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                CardHeading(title: "Calories eaten & burned", subtitle: "Last seven days · Cal")
                if energyBars.isEmpty {
                    emptyState("chart.bar.fill", text: "Add food or connect Apple Health to see the comparison.")
                } else {
                    Chart(energyBars) { bar in
                        BarMark(x: .value("Day", bar.day), y: .value("Calories", bar.calories))
                            .cornerRadius(4)
                            .foregroundStyle(by: .value("Series", bar.series))
                            .position(by: .value("Series", bar.series))
                            .accessibilityLabel("\(bar.day), \(bar.series)")
                            .accessibilityValue("\(USUnits.number(bar.calories)) Calories")
                    }
                    .chartXScale(domain: chartDays)
                    .chartXAxis {
                        AxisMarks(values: chartDays) { value in
                            AxisValueLabel {
                                if let key = value.as(String.self),
                                   let date = chartDates.first(where: { calendar.key(for: $0) == key }) {
                                    Text(calendar.format(date, style: .dateTime.weekday(.abbreviated))).font(.caption2)
                                }
                            }
                        }
                    }
                    .chartForegroundStyleScale(["Eaten": AppTheme.accent, "Burned": AppTheme.peachInk])
                    .frame(height: 220)
                }
                Text("Eaten means logged food. Burned means recorded active + resting energy, with gaps for missing readings. Today is still in progress.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private func emptyState(_ symbol: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(AppTheme.accent.opacity(0.5))
            Text(text).font(.subheadline).foregroundStyle(AppTheme.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
