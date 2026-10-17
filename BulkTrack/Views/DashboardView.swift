import SwiftUI
import SwiftData

struct DashboardView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .largeTitle) private var calorieSize = 48
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \DailyLog.date) private var logs: [DailyLog]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var scheduleOverrides: [WorkoutScheduleOverride]
    @Query private var sessions: [WorkoutSession]
    @State private var now = Date()
    @State private var tab = AppTab.today
    @State private var sheet: EntrySheet?
    @State private var editingWeight: WeightEntry?
    @State private var error: String?
    @State private var waterUndo: (key: String, milliliters: Double, expected: Double)?
    @State private var feedback = 0
    @State private var exportingWeight = false
    @State private var showWeightHistory = false
    @State private var weightToDelete: WeightEntry?
    @State private var deletedWeight: (date: Date, kg: Double, id: UUID, exported: Date?, version: Int)?

    private enum AppTab: Hashable { case today, nutrition, training, progress }
    private enum EntrySheet: String, Identifiable {
        case settings, food, weight
        var id: String { rawValue }
    }
    private var calendar: TrackingCalendar { profile.trackingCalendar }
    private var today: DailyLog? { logs.first { $0.dayKey == calendar.key(for: now) } }
    private var latestWeight: WeightEntry? { weights.last { $0.date <= now } }
    private var currentWeight: Double { latestWeight?.kilograms ?? profile.initialWeightKG }
    private var todayHealth: HealthDay? { health.days[calendar.key(for: now)] }
    private var overrides: [String: RoutineDay] {
        Dictionary(scheduleOverrides.compactMap { item in RoutineDay(rawValue: item.phaseRaw).map { (item.dayKey, $0) } }, uniquingKeysWith: { _, last in last })
    }
    private var phase: RoutineDay {
        TrainingSchedule.phase(on: now, anchor: profile.routineAnchor, calendar: calendar,
                               mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
    }
    private var activeSession: WorkoutSession? { sessions.first { $0.endedAt == nil } }
    private var plan: CaloriePlan {
        CalorieEngine.plan(input: profile.calorieInput(weightKG: currentWeight, now: now),
                           energy: todayHealth?.energy ?? EnergyReading(),
                           elapsedFraction: calendar.elapsedFraction(at: now))
    }
    private var attended: Set<String> { Set(logs.filter(\.gymAttended).map(\.dayKey)) }
    private var streak: Int {
        TrainingSchedule.streak(today: now, anchor: profile.routineAnchor, attended: attended,
                                calendar: calendar, mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            Text(calendar.format(now, style: .dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(.subheadline).foregroundStyle(AppTheme.secondary)
                            Spacer()
                            if health.isRefreshing { ProgressView().controlSize(.small).accessibilityLabel("Updating Health") }
                        }
                        fuelCard
                        trainingPreview
                        habitsCard
                        weightPreview
                    }.padding(20)
                }
                .background(AppTheme.background)
                .navigationTitle("Today").navigationBarTitleDisplayMode(.large)
                .toolbar { settingsButton }
                .refreshable { await refresh() }
            }.tabItem { Label("Today", systemImage: "square.grid.2x2") }.tag(AppTab.today)

            NavigationStack {
                NutritionDiaryView(profile: profile, now: now)
                    .toolbar { settingsButton }
            }.tabItem { Label("Nutrition", systemImage: "fork.knife") }.tag(AppTab.nutrition)

            NavigationStack {
                TrainingPlanView(profile: profile, now: now, attended: attended, streak: streak,
                                 toggleAttendance: toggleGym, updateDate: { now = Date() })
                    .toolbar { settingsButton }
            }.tabItem { Label("Training", systemImage: "dumbbell") }.tag(AppTab.training)

            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        milestoneCard
                        ProgressChartsView(weights: weights, logs: logs, healthDays: health.days,
                                           calendar: calendar, now: now, targetWeight: profile.targetWeightKG)
                        weightHistoryCard
                    }.padding(20)
                }
                .background(AppTheme.background).navigationTitle("Progress")
                .toolbar { settingsButton }
                .refreshable { await refresh() }
            }.tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(AppTab.progress)
        }
        .tint(AppTheme.accent).foregroundStyle(AppTheme.ink)
        .toolbarBackground(AppTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(item: $sheet, onDismiss: { now = Date() }) { item in
            switch item {
            case .settings: SettingsView(profile: profile, currentWeight: currentWeight)
            case .food: FoodEntryView(calendar: calendar)
            case .weight: WeightEntryView(currentKG: currentWeight)
            }
        }
        .sheet(item: $editingWeight) { entry in WeightEntryView(currentKG: currentWeight, editing: entry) }
        .confirmationDialog("Delete this weigh-in?", isPresented: Binding(get: { weightToDelete != nil }, set: { if !$0 { weightToDelete = nil } }), titleVisibility: .visible) {
            if let entry = weightToDelete {
                Button("Delete weigh-in", role: .destructive) { deleteWeight(entry) }
            }
        } message: { Text("This removes the local entry. Any copy already saved in Apple Health stays there.") }
        .alert("Couldn’t complete action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task(id: scenePhase) {
            guard scenePhase == .active else { health.stopObserving(); return }
            health.startObserving()
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await refresh()
            }
        }
        .onChange(of: health.revision) { _, _ in
            guard scenePhase == .active else { return }
            Task { await refresh() }
        }
    }

    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .settings } label: { Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Settings and goals")
        }
    }

    private var fuelCard: some View {
        let eaten = today?.calories ?? 0
        let remaining = max(0, plan.targetKcal - eaten)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("CALORIES REMAINING").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button { tab = .nutrition } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }
                    .foregroundStyle(AppTheme.lime).accessibilityLabel("Open nutrition diary")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number(remaining)).font(.system(size: calorieSize, weight: .semibold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
                Text("Cal").font(.title3).foregroundStyle(.white.opacity(0.7))
            }.foregroundStyle(.white)
            SoftProgress(value: eaten, goal: plan.targetKcal, color: AppTheme.lime)
            adaptiveRow {
                Text("\(number(eaten)) eaten")
                if !textSize.isAccessibilitySize { Spacer() }
                Text("Target: \(number(plan.targetKcal)) Cal · est.")
                    .accessibilityLabel("Estimated target: \(number(plan.targetKcal)) Calories")
            }.font(.caption).foregroundStyle(.white.opacity(0.8))
            Divider().overlay(.white.opacity(0.15))
            adaptiveRow {
                Label("Protein", systemImage: "fork.knife").font(.subheadline.weight(.medium))
                if !textSize.isAccessibilitySize { Spacer() }
                Text("\(number(today?.protein ?? 0)) / \(number(plan.proteinGrams)) g").font(.subheadline.weight(.semibold)).monospacedDigit()
            }.foregroundStyle(.white)
            PrimaryAction(title: "Log food", symbol: "plus", onDark: true) { sheet = .food }
        }.padding(22).background(AppTheme.hero, in: RoundedRectangle(cornerRadius: 24))
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: eaten)
    }

    private func adaptiveRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        return layout { content() }
    }
    private var trainingPreview: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconBadge(symbol: activeSession != nil || phase.isTraining ? "dumbbell" : "leaf", color: AppTheme.accent, background: AppTheme.sage)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeSession != nil ? "Workout in progress" : phase.title).font(.headline)
                        Text(today?.gymAttended == true ? "Logged today" : trainingSubtitle).font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Button { tab = .training } label: {
                    HStack {
                        Text(activeSession != nil ? "Resume workout" : phase.isTraining ? "Open workout" : "View schedule")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(PressButtonStyle())
            }
        }
    }
    private var trainingSubtitle: String {
        if phase.isTraining { return "\(streak) scheduled sessions in a row" }
        if phase == .planComplete { return "Extend your plan in Training" }
        return profile.routineMode.title
    }

    private var habitsCard: some View {
        SurfaceCard {
            VStack(spacing: 16) {
                HStack {
                    Label("Water", systemImage: "drop").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(number(USUnits.fluidOunces(today?.waterML ?? 0))) / \(number(USUnits.fluidOunces(profile.waterGoalML))) fl oz")
                        .font(.subheadline).monospacedDigit().foregroundStyle(AppTheme.secondary)
                }
                SoftProgress(value: today?.waterML ?? 0, goal: profile.waterGoalML, color: AppTheme.accent)
                HStack(spacing: 12) {
                    waterButton(8); waterButton(16)
                    Spacer(minLength: 0)
                    if let undo = waterUndo, undo.key == calendar.key(for: now), abs((today?.waterML ?? 0) - undo.expected) < 0.0001 {
                        Button("Undo") {
                            guard undo.key == calendar.key(for: Date()), abs((today?.waterML ?? 0) - undo.expected) < 0.0001 else { waterUndo = nil; now = Date(); return }
                            if mutateToday({ $0.waterML = max(0, $0.waterML - undo.milliliters) }) { waterUndo = nil }
                        }.font(.subheadline).frame(minHeight: 44)
                    }
                }
                Divider()
                let taken = (today?.creatineGrams ?? 0) >= profile.creatineGoalGrams
                Button {
                    mutateToday { $0.creatineGrams = $0.creatineGrams >= profile.creatineGoalGrams ? 0 : profile.creatineGoalGrams }
                } label: {
                    HStack {
                        Label("Creatine", systemImage: "pills").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(number(profile.creatineGoalGrams)) g").font(.subheadline).foregroundStyle(AppTheme.secondary)
                        Image(systemName: taken ? "checkmark.circle.fill" : "circle").font(.title2)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(taken ? "Taken today" : "Not taken")
                Divider()
                HStack {
                    Label("Sleep", systemImage: "moon").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let seconds = todayHealth?.sleepSeconds {
                        Text("\(number(seconds / 3600, digits: 1)) h").font(.subheadline.weight(.semibold))
                        Text("/ \(number(profile.sleepGoalHours)) h").font(.subheadline).foregroundStyle(AppTheme.secondary)
                    } else {
                        Button("No Health reading") { sheet = .settings }.font(.subheadline)
                    }
                }.frame(minHeight: 32)
            }
        }
    }
    private func waterButton(_ ounces: Double) -> some View {
        Button {
            let ml = USUnits.milliliters(ounces)
            var expected = 0.0
            if mutateToday({ $0.waterML += ml; expected = $0.waterML }) { waterUndo = (calendar.key(for: now), ml, expected) }
        } label: {
            Text("+\(number(ounces)) oz").font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
                .background(AppTheme.sage, in: Capsule())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("Add \(number(ounces)) fluid ounces of water")
    }
    private var weightPreview: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(latestWeight == nil ? "Starting weight" : "Latest weight").font(.caption).foregroundStyle(AppTheme.secondary)
                Text(USUnits.weight(currentWeight)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Spacer()
            Button("Log weight") { sheet = .weight }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.padding(.horizontal, 4)
    }
    private var milestoneCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardHeading(title: "Body weight", subtitle: "Goal \(USUnits.weight(profile.targetWeightKG))")
                    Spacer()
                    Button { sheet = .weight } label: { Image(systemName: "plus.circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Log weight")
                }
                Text(USUnits.weight(currentWeight)).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                if profile.targetWeightKG > profile.initialWeightKG {
                    SoftProgress(value: currentWeight - profile.initialWeightKG, goal: profile.targetWeightKG - profile.initialWeightKG, color: AppTheme.accent)
                }
                Text(latestWeight.map { "Measured \(calendar.format($0.date, style: .dateTime.month(.abbreviated).day()))" } ?? "Starting weight from your profile")
                    .font(.caption).foregroundStyle(AppTheme.secondary)
            }
        }
    }
    private var weightHistoryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeading(title: "Weigh-ins")
                    Spacer()
                    if weights.count > 5 { Button(showWeightHistory ? "Show less" : "See all") { showWeightHistory.toggle() }.font(.subheadline) }
                }
                if weights.isEmpty { Text("No weigh-ins yet.").font(.subheadline).foregroundStyle(AppTheme.secondary) }
                ForEach(Array(weights.filter { $0.date <= now }.reversed().prefix(showWeightHistory ? weights.count : 5))) { entry in
                    HStack {
                        Button { editingWeight = entry } label: {
                            HStack {
                                Text(calendar.format(entry.date, style: .dateTime.month(.abbreviated).day().hour().minute())).foregroundStyle(AppTheme.secondary)
                                Spacer()
                                Text(USUnits.weight(entry.kilograms)).fontWeight(.semibold).monospacedDigit()
                            }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Edit weigh-in")
                        Menu {
                            Button("Edit", systemImage: "pencil") { editingWeight = entry }
                            Button("Save to Apple Health", systemImage: "heart") { Task { await export(entry) } }.disabled(exportingWeight || !health.isAvailable)
                            Button("Delete", systemImage: "trash", role: .destructive) { weightToDelete = entry }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Weigh-in actions")
                    }
                }
                if deletedWeight != nil { Button("Undo deleted weigh-in", action: undoWeight).frame(minHeight: 44).font(.subheadline) }
            }
        }
    }
    private func deleteWeight(_ entry: WeightEntry) {
        let snapshot = (date: entry.date, kg: entry.kilograms, id: entry.id, exported: entry.healthExportedAt, version: entry.healthSyncVersion)
        do {
            try DiaryStore.save(context: context) { context.delete(entry) }
            deletedWeight = snapshot
            weightToDelete = nil
        } catch { self.error = error.localizedDescription }
    }
    private func undoWeight() {
        guard let item = deletedWeight else { return }
        do {
            let id = item.id
            let request = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })
            if try !context.fetch(request).isEmpty { deletedWeight = nil; return }
            try DiaryStore.save(context: context) {
                let entry = WeightEntry(date: item.date, kilograms: item.kg)
                entry.id = item.id; entry.healthExportedAt = item.exported; entry.healthSyncVersion = item.version
                context.insert(entry)
            }
            deletedWeight = nil
        } catch { self.error = error.localizedDescription }
    }
    private func number(_ value: Double, digits: Int = 0) -> String { USUnits.number(value, digits: digits) }
    @discardableResult private func mutateToday(_ change: (DailyLog) -> Void) -> Bool {
        now = Date()
        do {
            try DiaryStore.save(context: context) { change(try DiaryStore.day(for: now, calendar: calendar, context: context)) }
            feedback += 1; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func toggleGym(_ date: Date) {
        now = Date()
        guard calendar.start(of: date) <= calendar.start(of: now) else { return }
        do {
            try DiaryStore.save(context: context) {
                let day = try DiaryStore.day(for: date, calendar: calendar, context: context)
                day.gymAttended.toggle()
            }
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }
    private func refresh() async { now = Date(); await health.refresh(calendar: calendar) }
    private func export(_ entry: WeightEntry) async {
        exportingWeight = true
        defer { exportingWeight = false }
        do {
            let id = entry.id, kilograms = entry.kilograms, date = entry.date, version = entry.healthSyncVersion
            try await health.exportWeight(id: id, kilograms: kilograms, date: date, version: version)
            var request = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })
            request.fetchLimit = 1
            if let saved = try context.fetch(request).first,
               saved.healthSyncVersion == version, saved.kilograms == kilograms, saved.date == date {
                try DiaryStore.save(context: context) { saved.healthExportedAt = Date() }
            }
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }
}
