import SwiftUI
import SwiftData

struct NutritionDiaryView: View {
    let profile: UserProfile
    let now: Date
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dynamicTypeSize) private var textSize
    @Query(sort: \DailyLog.date) private var logs: [DailyLog]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @State private var selectedDate = Date()
    @State private var addingFood = false
    @State private var editing: FoodEntry?
    @State private var plannedMeal: PlannedMeal?
    @State private var error: String?
    @State private var showTarget = false
    @State private var showMeals = false
    @State private var showHabits = false
    @State private var habitDate = Date()
    @State private var water = ""
    @State private var creatine = ""
    @State private var deleted: DeletedFood?

    private struct DeletedFood {
        let id: UUID; let name: String; let date: Date; let kcal: Double
        let protein: Double?; let carbs: Double?; let fat: Double?; let favorite: Bool
    }
    private var calendar: TrackingCalendar { profile.trackingCalendar }
    private var key: String { calendar.key(for: selectedDate) }
    private var isToday: Bool { key == calendar.key(for: now) }
    private var day: DailyLog? { logs.first { $0.dayKey == key } }
    private var foods: [FoodEntry] { (day?.foods ?? []).sorted { $0.timestamp < $1.timestamp } }
    private var weight: Double { weights.last { $0.date <= now }?.kilograms ?? profile.initialWeightKG }
    private var plan: CaloriePlan {
        CalorieEngine.plan(input: profile.calorieInput(weightKG: weight, now: now),
                           energy: health.days[calendar.key(for: now)]?.energy ?? EnergyReading(),
                           elapsedFraction: calendar.elapsedFraction(at: now))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dateNavigation
                summaryCard
                PrimaryAction(title: "Log food", symbol: "plus") { addingFood = true }
                foodList
                if CalendarFitnessPlan.isActive(on: selectedDate, calendar: calendar) { mealSuggestions }
                habitsHistory
                if isToday { targetDetails }
            }.padding(20)
        }
        .background(AppTheme.background).navigationTitle("Nutrition")
        .sheet(isPresented: $addingFood) { FoodEntryView(calendar: calendar, initialDate: entryDate) }
        .sheet(item: $editing) { FoodEntryView(calendar: calendar, editing: $0) }
        .sheet(item: $plannedMeal) { FoodEntryView(calendar: calendar, preset: $0, initialDate: entryDate) }
        .alert("Couldn’t save change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: key) { _, _ in deleted = nil }
        .onChange(of: now) { old, new in
            if calendar.key(for: selectedDate) == calendar.key(for: old), calendar.key(for: old) != calendar.key(for: new) { selectedDate = new }
        }
        .sheet(isPresented: $showHabits) { habitEditor }
    }
    private var entryDate: Date {
        isToday ? Date() : calendar.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }
    private var dateNavigation: some View {
        HStack(spacing: 8) {
            Button { selectedDate = calendar.adding(days: -1, to: selectedDate) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("Previous day")
            DatePicker("Diary date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden().frame(maxWidth: .infinity)
            Button { selectedDate = min(Date(), calendar.adding(days: 1, to: selectedDate)) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.disabled(isToday).accessibilityLabel("Next day")
            if !isToday && !textSize.isAccessibilitySize { Button("Today") { selectedDate = Date() }.font(.subheadline).frame(minHeight: 44) }
        }
    }
    private var summaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(USUnits.number(day?.calories ?? 0))").font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text("Cal logged").font(.subheadline).foregroundStyle(AppTheme.secondary)
                    Spacer(minLength: 0)
                }
                if isToday { SoftProgress(value: day?.calories ?? 0, goal: plan.targetKcal, color: AppTheme.accent) }
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    macro("Protein", value: day?.protein ?? 0, goal: plan.proteinGrams)
                    macro("Carbs", value: day?.carbs ?? 0, goal: plan.carbGrams)
                    macro("Fat", value: day?.fat ?? 0, goal: plan.fatGrams)
                }
                if let count = day?.entriesMissingMacros, count > 0 {
                    Label("\(count) \(count == 1 ? "entry has" : "entries have") incomplete macros", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
        }
    }
    private func macro(_ title: String, value: Double, goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondary)
            Text("\(USUnits.number(value)) g").font(.headline).monospacedDigit()
            if isToday { Text("of \(USUnits.number(goal)) g").font(.caption).foregroundStyle(AppTheme.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var foodList: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeading(title: "Food diary", subtitle: foods.isEmpty ? nil : "\(foods.count) \(foods.count == 1 ? "entry" : "entries")")
                if foods.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("No food logged").font(.headline)
                        Text("Add a meal, snack, or quick calorie entry.").font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }.padding(.vertical, 10)
                }
                ForEach(foods) { food in
                    HStack(alignment: .center, spacing: 6) {
                        Button { editing = food } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(food.name).font(.subheadline.weight(.semibold))
                                Text("\(USUnits.number(food.calories)) Cal\(food.proteinGrams.map { " · \(USUnits.number($0)) g protein" } ?? "")")
                                    .font(.caption).foregroundStyle(AppTheme.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Edit food entry")
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = food }
                            Button(food.isFavorite ? "Remove favorite" : "Favorite", systemImage: food.isFavorite ? "star.slash" : "star") { favorite(food) }
                            Button("Repeat today", systemImage: "plus.square.on.square") { repeatToday(food) }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(food) }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Actions for \(food.name)")
                    }
                    if food.id != foods.last?.id { Divider() }
                }
                if deleted != nil {
                    HStack { Text("Entry deleted").font(.caption).foregroundStyle(AppTheme.secondary); Spacer(); Button("Undo", action: undoDelete).frame(minHeight: 44) }
                }
            }
        }
    }
    private var mealSuggestions: some View {
        SurfaceCard {
            DisclosureGroup(isExpanded: $showMeals) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved from your Fitness calendar. Suggestions count only when you log them.")
                        .font(.caption).foregroundStyle(AppTheme.secondary).padding(.top, 8)
                    ForEach(CalendarFitnessPlan.meals(on: selectedDate, calendar: calendar)) { meal in
                        Button { plannedMeal = meal } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.title + (meal.optional ? " · optional" : "")).font(.subheadline.weight(.medium))
                                    Text(meal.venue).font(.caption).foregroundStyle(AppTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                            }.frame(minHeight: 52)
                        }.buttonStyle(.plain)
                    }
                }
            } label: { Text("Meal suggestions").font(.headline) }
        }
    }
    private var habitsHistory: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardHeading(title: "Daily habits")
                    Spacer()
                    Button("Edit") {
                        habitDate = selectedDate
                        water = USUnits.number(USUnits.fluidOunces(day?.waterML ?? 0), digits: 1)
                        creatine = USUnits.number(day?.creatineGrams ?? 0, digits: 1)
                        showHabits = true
                    }.frame(minHeight: 44).font(.subheadline)
                }
                HStack {
                    Label("\(USUnits.number(USUnits.fluidOunces(day?.waterML ?? 0))) fl oz", systemImage: "drop")
                    Spacer()
                    Label("\(USUnits.number(day?.creatineGrams ?? 0)) g creatine", systemImage: "pills")
                }.font(.subheadline).foregroundStyle(AppTheme.secondary)
            }
        }
    }
    private var targetDetails: some View {
        SurfaceCard {
            DisclosureGroup(isExpanded: $showTarget) {
                VStack(spacing: 12) {
                    detailRow("Full-day resting estimate", value: plan.restingKcal)
                    detailRow("Full-day active allowance", value: plan.activeKcal)
                    detailRow("Surplus", value: plan.surplusKcal)
                    Divider()
                    detailRow("Today’s calorie target", value: plan.targetKcal)
                    Text("The active allowance is the greater of your planned activity or Health’s recorded active energy. The resting estimate includes the rest of today. These are estimates; the Progress tab shows your measured weight trend.")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                    if let last = health.lastRefresh {
                        Text("Health updated \(last, style: .relative) ago").font(.caption).foregroundStyle(AppTheme.secondary)
                    } else { Text("No Health update. Your profile supplies the estimate.").font(.caption).foregroundStyle(AppTheme.secondary) }
                }.padding(.top, 14)
            } label: { Text("Why this calorie target?").font(.subheadline.weight(.medium)) }
        }
    }
    private func detailRow(_ title: String, value: Double) -> some View {
        HStack { Text(title); Spacer(); Text("\(USUnits.number(value)) Cal").monospacedDigit() }.font(.caption)
    }
    private var habitEditor: some View {
        NavigationStack {
            Form {
                Section(calendar.format(habitDate, style: .dateTime.month().day())) {
                    DecimalField(title: "Water · fl oz", text: $water)
                    DecimalField(title: "Creatine · g", text: $creatine)
                }
            }.dismissibleKeyboard().navigationTitle("Daily habits").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showHabits = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveHabits() }.disabled(!NumericInput.valid(water, in: 0...600) || !NumericInput.valid(creatine, in: 0...50))
                    }
                }
        }
    }
    private func saveHabits() {
        guard let oz = NumericInput.value(water), let grams = NumericInput.value(creatine), (0...600).contains(oz), (0...50).contains(grams) else { return }
        write {
            let log = try DiaryStore.day(for: habitDate, calendar: calendar, context: context)
            log.waterML = USUnits.milliliters(oz); log.creatineGrams = grams
        }
        if error == nil { showHabits = false }
    }
    private func favorite(_ food: FoodEntry) { write { food.isFavorite.toggle() } }
    private func repeatToday(_ food: FoodEntry) {
        write {
            let log = try DiaryStore.day(for: Date(), calendar: calendar, context: context)
            let copy = FoodEntry(name: food.name, timestamp: Date(), calories: food.calories, proteinGrams: food.proteinGrams, carbGrams: food.carbGrams, fatGrams: food.fatGrams)
            copy.isFavorite = food.isFavorite
            context.insert(copy); log.foods.append(copy)
        }
        if error == nil { selectedDate = Date() }
    }
    private func delete(_ food: FoodEntry) {
        let item = DeletedFood(id: food.id, name: food.name, date: food.timestamp, kcal: food.calories, protein: food.proteinGrams, carbs: food.carbGrams, fat: food.fatGrams, favorite: food.isFavorite)
        write { context.delete(food) }
        if error == nil { deleted = item }
    }
    private func undoDelete() {
        guard let item = deleted else { return }
        write {
            let id = item.id
            let request = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })
            guard try context.fetch(request).isEmpty else { return }
            let log = try DiaryStore.day(for: item.date, calendar: calendar, context: context)
            let food = FoodEntry(name: item.name, timestamp: item.date, calories: item.kcal, proteinGrams: item.protein, carbGrams: item.carbs, fatGrams: item.fat)
            food.id = item.id; food.isFavorite = item.favorite
            context.insert(food); log.foods.append(food)
        }
        if error == nil { deleted = nil }
    }
    private func write(_ changes: () throws -> Void) {
        error = nil
        do { try DiaryStore.save(context: context, changes: changes) } catch { self.error = error.localizedDescription }
    }
}
