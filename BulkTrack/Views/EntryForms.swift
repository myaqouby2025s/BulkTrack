import SwiftUI
import SwiftData

struct DecimalField: View {
    let title: String
    @Binding var text: String
    var placeholder = "0"
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(title).accessibilityHidden(true)
            if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
            TextField(placeholder, text: $text)
                .multilineTextAlignment(textSize.isAccessibilitySize ? .leading : .trailing)
                .keyboardType(.decimalPad).focused($focused)
                .foregroundStyle(AppTheme.ink).font(.body.monospacedDigit())
                .accessibilityLabel(title).accessibilityIdentifier(title)
                .frame(minWidth: 64, maxWidth: textSize.isAccessibilitySize ? .infinity : 130)
        }.contentShape(Rectangle()).onTapGesture { focused = true }
    }
}

struct ProfileEditorView: View {
    let profile: UserProfile?
    let currentKG: Double?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var feet: String
    @State private var inches: String
    @State private var weight: String
    @State private var target: String
    @State private var birthday: Date
    @State private var automaticResting: Bool
    @State private var calculationProfile: RestingEquation
    @State private var manualResting: String
    @State private var active: String
    @State private var surplus: String
    @State private var protein: String
    @State private var water: String
    @State private var sleep: String
    @State private var anchor: Date
    @State private var routine: RoutineMode
    @State private var continuePlan: Bool
    @State private var error: String?

    init(profile: UserProfile?, currentKG: Double? = nil) {
        self.profile = profile
        self.currentKG = currentKG
        let parts = USUnits.heightParts(profile?.heightCM ?? 175)
        _feet = State(initialValue: String(parts.feet))
        _inches = State(initialValue: String(parts.inches))
        _weight = State(initialValue: USUnits.number(USUnits.pounds(currentKG ?? profile?.initialWeightKG ?? 70), digits: 1))
        _target = State(initialValue: USUnits.number(USUnits.pounds(profile?.targetWeightKG ?? 80), digits: 1))
        _birthday = State(initialValue: profile?.birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date())
        let savedEquation = RestingEquation(rawValue: profile?.restingEquationRaw ?? "") ?? .male
        _automaticResting = State(initialValue: savedEquation != .manual)
        _calculationProfile = State(initialValue: savedEquation == .female ? .female : .male)
        _manualResting = State(initialValue: USUnits.number(profile?.manualRestingKcal ?? 1700))
        _active = State(initialValue: USUnits.number(profile?.plannedActiveKcal ?? 350))
        _surplus = State(initialValue: USUnits.number(profile?.surplusKcal ?? 250))
        let proteinValue = profile.map { $0.proteinGoalGrams > 0 ? $0.proteinGoalGrams : (currentKG ?? $0.initialWeightKG) * $0.proteinGramsPerKG } ?? (70 * 1.8)
        _protein = State(initialValue: USUnits.number(proteinValue))
        _water = State(initialValue: USUnits.number(USUnits.fluidOunces(profile?.waterGoalML ?? USUnits.milliliters(80)), digits: 1))
        _sleep = State(initialValue: USUnits.number(profile?.sleepGoalHours ?? 8, digits: 1))
        _anchor = State(initialValue: profile?.routineAnchor ?? Date())
        _routine = State(initialValue: profile?.routineMode ?? .threeDayFullBody)
        _continuePlan = State(initialValue: profile?.routineEndDate == nil)
    }

    private var heightCM: Double? {
        guard let ft = Int(feet), (3...8).contains(ft), let inch = NumericInput.value(inches),
              inch >= 0, inch < 12 else { return nil }
        return USUnits.centimeters(feet: ft, inches: inch)
    }

    private var equation: RestingEquation { automaticResting ? calculationProfile : .manual }

    private var restingPreview: Double? {
        guard let heightCM, let pounds = NumericInput.value(weight), (66...772).contains(pounds) else { return nil }
        let age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
        guard (18...100).contains(age) else { return nil }
        let input = CalorieInput(weightKG: USUnits.kilograms(pounds), heightCM: heightCM, ageYears: age,
                                 equation: calculationProfile, manualRestingKcal: 1700,
                                 plannedActiveKcal: 0, surplusKcal: 0, targetWeightKG: 0,
                                 proteinGramsPerKG: 1.8)
        return CalorieEngine.restingCalories(for: input)
    }

    private var validationMessage: String? {
        guard let heightCM, (120...230).contains(heightCM) else { return "Enter a height between 4′0″ and 7′6″, with inches from 0 to 11." }
        let age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
        if !(18...100).contains(age) { return "This profile supports ages 18–100. Check your date of birth." }
        if !NumericInput.valid(weight, in: 66...772) { return "Enter a weight between 66 and 772 lb." }
        if !NumericInput.valid(target, in: 66...772) { return "Enter a goal between 66 and 772 lb." }
        if !automaticResting && !NumericInput.valid(manualResting, in: 500...6000) {
            return "Enter resting Calories between 500 and 6,000, or turn on automatic estimation."
        }
        if !NumericInput.valid(active, in: 0...4000) { return "Enter an activity allowance between 0 and 4,000 Calories." }
        if !NumericInput.valid(surplus, in: 0...1000) { return "Enter a surplus between 0 and 1,000 Calories." }
        if !NumericInput.valid(protein, in: 20...400) { return "Enter a protein goal between 20 and 400 grams." }
        if !NumericInput.valid(water, in: 8...338) { return "Enter a water goal between 8 and 338 fl oz." }
        if !NumericInput.valid(sleep, in: 4...12) { return "Enter a sleep goal between 4 and 12 hours." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        BulkTrackBrand()
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile == nil ? "Set up your plan" : "Profile & goals")
                                .font(.title2.bold())
                            Text(profile == nil ? "Enter your measurements to personalize your daily targets." : "Adjust the targets used throughout your diary.")
                                .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        }
                    }.padding(.vertical, 12).listRowBackground(Color.clear)
                }
                Section("Your measurements") {
                    HStack {
                        DecimalField(title: "Feet", text: $feet)
                        Divider().padding(.horizontal, 8)
                        DecimalField(title: "Inches", text: $inches)
                    }
                    if profile == nil {
                        DecimalField(title: "Starting weight · lb", text: $weight)
                    } else {
                        LabeledContent("Latest weight", value: "\(weight) lb")
                    }
                    DecimalField(title: "Goal weight · lb", text: $target)
                    DatePicker("Date of birth", selection: $birthday, in: ...Date(), displayedComponents: .date)
                    if profile == nil {
                        Text("The prefilled numbers are examples. Enter your current measurements and birthday before saving.")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                }
                Section {
                    Toggle("Estimate automatically", isOn: $automaticResting)
                        .accessibilityIdentifier("automaticResting")
                        .accessibilityHint("Turn off to enter your own resting Calories.")
                    if automaticResting {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sex used by the estimate").font(.subheadline)
                            Picker("Sex used by the estimate", selection: $calculationProfile) {
                                Text("Male").tag(RestingEquation.male)
                                Text("Female").tag(RestingEquation.female)
                            }.pickerStyle(.segmented)
                        }.padding(.vertical, 4)
                        if let restingPreview {
                            LabeledContent("Estimated resting burn",
                                           value: "\(USUnits.number(restingPreview)) Cal / day")
                                .font(.subheadline)
                        }
                    } else {
                        DecimalField(title: "Resting Calories / day", text: $manualResting, placeholder: "Enter Calories")
                    }
                } header: { Text("Resting Calories") } footer: {
                    Text(automaticResting
                         ? "Energy your body uses at rest. We estimate it from your weight, height, age and the sex-specific formula. Activity and your surplus are added separately."
                         : "Enter a resting-energy number from a measurement or your own estimate. Leave out exercise and other activity.")
                }
                Section("Daily goals") {
                    DecimalField(title: "Protein · grams", text: $protein)
                    DecimalField(title: "Water · fl oz", text: $water)
                    DecimalField(title: "Sleep · hours", text: $sleep)
                    LabeledContent("Creatine", value: "5 g")
                    Text("Choose your daily protein goal. Nutrition uses grams, just like US food labels.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
                Section("Training rhythm") {
                    Picker("Schedule", selection: $routine) {
                        ForEach(RoutineMode.allCases) { Text($0.title).tag($0) }
                    }
                    if profile == nil {
                        DatePicker("Plan starts", selection: $anchor, in: ...Date(), displayedComponents: .date)
                    }
                    if let end = profile?.routineEndDate {
                        LabeledContent("Calendar plan ends", value: end.formatted(date: .abbreviated, time: .omitted))
                        Toggle("Continue this rhythm after the plan", isOn: $continuePlan)
                    }
                    Text(routine.detail + ". Scheduled rest days preserve your streak.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                    if let profile, routine != profile.routineMode {
                        Text("Switching schedules starts a new streak today. Your past attendance stays saved.")
                            .font(.footnote).foregroundStyle(AppTheme.peachInk)
                    }
                }
                Section {
                    DisclosureGroup("Calorie settings") {
                        DecimalField(title: "Activity allowance · Cal", text: $active)
                        DecimalField(title: "Daily surplus · Cal", text: $surplus)
                        Text("Your target adds resting energy, an activity allowance and extra calories for gaining. Recorded activity can raise it automatically. The extra allowance stops at your long-term goal.")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                    LabeledContent("Diary time zone", value: profile?.trackingTimeZoneID ?? TimeZone.current.identifier)
                        .font(.footnote)
                }
                if let message = validationMessage {
                    Section { Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(AppTheme.peachInk) }
                }
            }
            .dismissibleKeyboard()
            .onChange(of: automaticResting) { _, _ in KeyboardControl.dismiss() }
            .onChange(of: calculationProfile) { _, _ in KeyboardControl.dismiss() }
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .navigationTitle(profile == nil ? "Welcome to BulkTrack" : "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if profile != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(profile == nil ? "Create plan" : "Save", action: save).fontWeight(.semibold)
                        .disabled(validationMessage != nil)
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard validationMessage == nil, let heightCM,
              let pounds = NumericInput.value(weight), let goalPounds = NumericInput.value(target),
              let activityCalories = NumericInput.value(active), let surplusCalories = NumericInput.value(surplus),
              let proteinGrams = NumericInput.value(protein), let waterOunces = NumericInput.value(water),
              let sleepHours = NumericInput.value(sleep) else { return }
        do {
            try DiaryStore.save(context: context) {
                let zone = profile?.trackingTimeZoneID ?? TimeZone.current.identifier
                let tracking = TrackingCalendar(timeZoneID: zone)
                let kg = USUnits.kilograms(pounds)
                let targetKG = USUnits.kilograms(goalPounds)
                let saved = profile ?? UserProfile(heightCM: heightCM, initialWeightKG: kg,
                                                   targetWeightKG: targetKG, birthDate: birthday,
                                                   equation: equation, routineAnchor: tracking.start(of: anchor),
                                                   trackingTimeZoneID: zone)
                if profile == nil {
                    context.insert(saved)
                    context.insert(WeightEntry(date: Date(), kilograms: kg))
                }
                if let profile, profile.routineMode != routine {
                    saved.routineAnchor = tracking.start(of: Date())
                    saved.routineEndDate = nil
                } else if let profile, continuePlan, let end = profile.routineEndDate {
                    saved.routineEndDate = nil
                    if tracking.start(of: Date()) > tracking.start(of: end) {
                        saved.routineAnchor = tracking.start(of: Date())
                    }
                }
                saved.heightCM = heightCM
                saved.targetWeightKG = targetKG
                saved.birthDate = birthday
                saved.restingEquationRaw = equation.rawValue
                if let manual = NumericInput.value(manualResting), (500...6000).contains(manual) {
                    saved.manualRestingKcal = manual
                }
                saved.plannedActiveKcal = activityCalories
                saved.surplusKcal = surplusCalories
                saved.proteinGoalGrams = proteinGrams
                saved.waterGoalML = USUnits.milliliters(waterOunces)
                saved.sleepGoalHours = sleepHours
                saved.routineModeRaw = routine.rawValue
                if profile == nil && routine == .twoOnOneOff { saved.calendarPlanVersion = -1 }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct FoodEntryView: View {
    let calendar: TrackingCalendar
    let preset: PlannedMeal?
    let editing: FoodEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \FoodEntry.timestamp, order: .reverse) private var entries: [FoodEntry]
    @State private var name: String
    @State private var date: Date
    @State private var calories: String
    @State private var includeMacros: Bool
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var portion = "1"
    @State private var favorite: Bool
    @State private var favoritesOnly = false
    @State private var error: String?

    init(calendar: TrackingCalendar, preset: PlannedMeal? = nil, editing: FoodEntry? = nil, initialDate: Date? = nil) {
        self.calendar = calendar
        self.preset = preset
        self.editing = editing
        _name = State(initialValue: editing?.name ?? preset?.title ?? "")
        _date = State(initialValue: editing?.timestamp ?? initialDate ?? Date())
        _calories = State(initialValue: editing.map { USUnits.number($0.calories, digits: 1) } ?? "")
        _protein = State(initialValue: editing?.proteinGrams.map { USUnits.number($0, digits: 1) } ?? "")
        _carbs = State(initialValue: editing?.carbGrams.map { USUnits.number($0, digits: 1) } ?? "")
        _fat = State(initialValue: editing?.fatGrams.map { USUnits.number($0, digits: 1) } ?? "")
        _includeMacros = State(initialValue: editing == nil || editing?.proteinGrams != nil || editing?.carbGrams != nil || editing?.fatGrams != nil)
        _favorite = State(initialValue: editing?.isFavorite ?? false)
    }

    private func optionalMacro(_ text: String) -> Double? {
        includeMacros ? NumericInput.value(text) : nil
    }
    private var portionValue: Double? { NumericInput.value(portion) }
    private var proteinValue: Double? { optionalMacro(protein).flatMap { grams in portionValue.map { grams * $0 } } }
    private var carbsValue: Double? { optionalMacro(carbs).flatMap { grams in portionValue.map { grams * $0 } } }
    private var fatValue: Double? { optionalMacro(fat).flatMap { grams in portionValue.map { grams * $0 } } }
    private var effectiveCalories: Double? {
        guard let multiplier = portionValue else { return nil }
        if !calories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NumericInput.value(calories).map { $0 * multiplier }
        }
        guard let p = proteinValue, let c = carbsValue, let f = fatValue else { return nil }
        return 4 * p + 4 * c + 9 * f
    }
    private var validationMessage: String? {
        if !NumericInput.valid(portion, in: 0.1...10) { return "Enter a serving amount from 0.1 to 10." }
        if includeMacros {
            for (text, title, limit) in [(protein, "protein", 1000.0), (carbs, "carbs", 2000.0), (fat, "fat", 1000.0)] {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !NumericInput.valid(text, in: 0...limit) {
                    return "Check the \(title) amount. Use a number or leave it blank."
                }
            }
        }
        guard let kcal = effectiveCalories, kcal.isFinite, (0.1...20000).contains(kcal) else {
            return "Enter Calories, or enter all three macros to calculate them. Total must be under 20,000 Cal."
        }
        if let value = proteinValue, value > 1000 { return "Total protein must be 1,000 g or less." }
        if let value = carbsValue, value > 2000 { return "Total carbs must be 2,000 g or less." }
        if let value = fatValue, value > 1000 { return "Total fat must be 1,000 g or less." }
        if date > Date() { return "Choose a time that has already passed." }
        return nil
    }
    private var valid: Bool { validationMessage == nil }
    private var suggestions: [FoodEntry] {
        // A saved portion is reusable as one serving. Identical entries appear only once.
        var seen = Set<String>()
        let candidates = favoritesOnly ? entries.filter(\.isFavorite) : entries
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { food in
            let key = [food.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                       String(food.calories), food.proteinGrams.map { String($0) } ?? "?",
                       food.carbGrams.map { String($0) } ?? "?", food.fatGrams.map { String($0) } ?? "?"].joined(separator: "|")
            guard seen.insert(key).inserted else { return false }
            return query.isEmpty || food.name.localizedCaseInsensitiveContains(query)
        }.prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal, food or snack", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Food name")
                    DatePicker("When", selection: $date, in: ...Date())
                } header: { Text("Food") }
                if editing == nil, !entries.isEmpty {
                    Section {
                        Picker("Saved foods", selection: $favoritesOnly) {
                            Text("Recent").tag(false)
                            Text("Favorites").tag(true)
                        }.pickerStyle(.segmented)
                        ForEach(suggestions) { food in suggestionRow(food) }
                        if suggestions.isEmpty {
                            Text(favoritesOnly ? "Save a food as a favorite to find it here." : "No matching food. Enter a new one below.")
                                .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        }
                    } header: { Text("Use again") } footer: {
                        Text("Tap a food to fill its saved portion, then adjust the amount and add it.")
                    }
                }
                Section {
                    DecimalField(title: "Calories", text: $calories)
                    Toggle("Include macros", isOn: $includeMacros)
                    if includeMacros {
                        DecimalField(title: "Protein · g", text: $protein, placeholder: "Unknown")
                        DecimalField(title: "Carbs · g", text: $carbs, placeholder: "Unknown")
                        DecimalField(title: "Fat · g", text: $fat, placeholder: "Unknown")
                    }
                } header: { Text("Nutrition per serving") } footer: {
                    Text(includeMacros
                         ? "Leave unknown macros blank. Calories can be calculated when all three macros are entered."
                         : "This food’s macros will be marked incomplete.")
                }
                Section {
                    DecimalField(title: "Servings", text: $portion, placeholder: "1")
                    HStack(spacing: 8) {
                        ForEach([0.5, 1, 1.5, 2], id: \.self) { amount in
                            Button(USUnits.number(amount, digits: amount.rounded() == amount ? 0 : 1)) {
                                KeyboardControl.dismiss()
                                portion = String(amount)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(portionValue == amount ? AppTheme.sage : AppTheme.background, in: Capsule())
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(amount) servings")
                        }
                    }
                    Toggle("Save as favorite", isOn: $favorite)
                } header: { Text("Portion") }
                if let kcal = effectiveCalories, valid {
                    Section {
                        LabeledContent("Total", value: "\(USUnits.number(kcal)) Cal")
                            .font(.headline)
                        if includeMacros {
                            Text("Protein \(macroSummary(proteinValue))  ·  Carbs \(macroSummary(carbsValue))  ·  Fat \(macroSummary(fatValue))")
                                .font(.footnote).foregroundStyle(AppTheme.secondary)
                        }
                    }
                } else if let message = validationMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(AppTheme.secondary) }
                }
                if let preset {
                    Section("Calendar suggestion") {
                        Text(preset.suggestion).font(.subheadline)
                        Text(preset.nutrition).font(.footnote).foregroundStyle(AppTheme.secondary)
                        Text("Enter the nutrition for what you actually ate. This plan is a reference; nothing is logged until you tap Add.")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                }
            }
            .dismissibleKeyboard()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: includeMacros)
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .navigationTitle(editing == nil ? "Add food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save", action: save).fontWeight(.semibold).disabled(!valid)
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func macroSummary(_ grams: Double?) -> String {
        grams.map { "\(USUnits.number($0, digits: 1)) g" } ?? "—"
    }

    private func suggestionRow(_ food: FoodEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                KeyboardControl.dismiss()
                name = food.name
                calories = USUnits.number(food.calories, digits: 1)
                protein = food.proteinGrams.map { USUnits.number($0, digits: 1) } ?? ""
                carbs = food.carbGrams.map { USUnits.number($0, digits: 1) } ?? ""
                fat = food.fatGrams.map { USUnits.number($0, digits: 1) } ?? ""
                includeMacros = food.proteinGrams != nil || food.carbGrams != nil || food.fatGrams != nil
                portion = "1"
                favorite = food.isFavorite
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).foregroundStyle(AppTheme.ink)
                    Text("\(USUnits.number(food.calories)) Cal · \(food.proteinGrams.map { "\(USUnits.number($0)) g protein" } ?? "Protein unknown")")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.borderless)
            Button {
                do { try DiaryStore.save(context: context) { food.isFavorite.toggle() } }
                catch { self.error = error.localizedDescription }
            } label: {
                Image(systemName: food.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(AppTheme.accent).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.borderless)
                .accessibilityLabel(food.isFavorite ? "Remove \(food.name) from favorites" : "Favorite \(food.name)")
        }
    }

    private func save() {
        guard valid, let kcal = effectiveCalories else { return }
        do {
            try DiaryStore.save(context: context) {
                let day = try DiaryStore.day(for: date, calendar: calendar, context: context)
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let editing {
                    // Reassign the inverse relationship rather than deleting/recreating a diary item.
                    // Removing it through a cascading parent can destroy the record being moved.
                    editing.day = day
                    editing.name = trimmed.isEmpty ? "Quick entry" : trimmed
                    editing.timestamp = date
                    editing.calories = kcal
                    editing.proteinGrams = proteinValue
                    editing.carbGrams = carbsValue
                    editing.fatGrams = fatValue
                    editing.isFavorite = favorite
                } else {
                    let food = FoodEntry(name: trimmed.isEmpty ? "Quick entry" : trimmed,
                                         timestamp: date, calories: kcal, proteinGrams: proteinValue,
                                         carbGrams: carbsValue, fatGrams: fatValue)
                    food.isFavorite = favorite
                    context.insert(food)
                    food.day = day
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct WeightEntryView: View {
    let currentKG: Double
    let editing: WeightEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var weight: String
    @State private var date: Date
    @State private var error: String?

    init(currentKG: Double, editing: WeightEntry? = nil) {
        self.currentKG = currentKG
        self.editing = editing
        _weight = State(initialValue: USUnits.number(USUnits.pounds(editing?.kilograms ?? currentKG), digits: 1))
        _date = State(initialValue: editing?.date ?? Date())
    }

    private var valid: Bool { NumericInput.valid(weight, in: 66...772) && date <= Date() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DecimalField(title: "Body weight · lb", text: $weight)
                    DatePicker("Measured", selection: $date, in: ...Date())
                } footer: {
                    Text("Use similar conditions each time, such as in the morning before breakfast. Weekly averages smooth out daily changes.")
                }
                if editing?.healthExportedAt != nil {
                    Section {
                        Label("After changing this entry, export it again from Progress to update Apple Health.", systemImage: "heart")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                }
                if !NumericInput.valid(weight, in: 66...772) {
                    Section { Text("Enter a weight between 66 and 772 lb.").font(.footnote).foregroundStyle(AppTheme.secondary) }
                }
            }
            .dismissibleKeyboard()
            .scrollContentBackground(.hidden).background(AppTheme.background).foregroundStyle(AppTheme.ink)
            .tint(AppTheme.accent)
            .navigationTitle(editing == nil ? "Log weight" : "Edit weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!valid)
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard valid, let lb = NumericInput.value(weight) else { return }
        do {
            try DiaryStore.save(context: context) {
                let kg: Double
                if let editing, weight == USUnits.number(USUnits.pounds(editing.kilograms), digits: 1) {
                    kg = editing.kilograms
                } else {
                    kg = USUnits.kilograms(lb)
                }
                if let editing {
                    if abs(editing.kilograms - kg) > 0.0001 || editing.date != date {
                        editing.healthSyncVersion += 1
                        editing.healthExportedAt = nil
                    }
                    editing.kilograms = kg
                    editing.date = date
                } else {
                    context.insert(WeightEntry(date: date, kilograms: kg))
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct WorkoutSetEntryView: View {
    let exercise: PlannedExercise
    let editing: WorkoutSet?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date, order: .reverse) private var history: [WorkoutSet]
    @State private var load: String
    @State private var reps: String
    @State private var date: Date
    @State private var error: String?

    init(exercise: PlannedExercise, editing: WorkoutSet? = nil) {
        self.exercise = exercise
        self.editing = editing
        _load = State(initialValue: editing.map { USUnits.number(USUnits.pounds($0.kilograms), digits: 1) } ?? "")
        _reps = State(initialValue: editing.map { String($0.reps) } ?? "")
        _date = State(initialValue: editing?.date ?? Date())
    }

    private var valid: Bool {
        NumericInput.valid(load, in: 0...2000) && Int(reps).map { (1...(exercise.isTimed ? 300 : 100)).contains($0) } == true && date <= Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exercise.name).font(.headline)
                    Text("\(exercise.sets) sets · \(exercise.reps)\(exercise.isTimed ? "" : " reps")")
                        .font(.subheadline).foregroundStyle(AppTheme.secondary)
                }
                Section("Set") {
                    DecimalField(title: "Weight · lb", text: $load)
                    LabeledContent(exercise.isTimed ? "Seconds" : "Reps") {
                        TextField(exercise.isTimed ? "30" : "8", text: $reps)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel(exercise.isTimed ? "Seconds" : "Reps")
                    }
                    if editing?.sessionID == nil {
                        DatePicker("When", selection: $date, in: ...Date())
                    } else {
                        LabeledContent("Workout date", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Section {
                    Text("Enter 0 lb for bodyweight movements. For dumbbells, consistently use the weight of one dumbbell.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }
            .dismissibleKeyboard()
            .scrollContentBackground(.hidden).background(AppTheme.background).foregroundStyle(AppTheme.ink)
            .tint(AppTheme.accent)
            .navigationTitle(editing == nil ? "Log set" : "Edit set").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard editing == nil, load.isEmpty else { return }
                let unit = exercise.isTimed ? "seconds" : "reps"
                let last = history.first { $0.exerciseID == exercise.id && $0.unitRaw == unit }
                load = last.map { USUnits.number(USUnits.pounds($0.kilograms), digits: 1) } ?? "0"
                reps = last.map { String($0.reps) } ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!valid)
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard valid, let pounds = NumericInput.value(load), let count = Int(reps) else { return }
        do {
            try DiaryStore.save(context: context) {
                let set = editing ?? WorkoutSet(date: date, exerciseID: exercise.id,
                                                kilograms: USUnits.kilograms(pounds), reps: count)
                set.date = date
                if editing == nil || load != USUnits.number(USUnits.pounds(set.kilograms), digits: 1) {
                    set.kilograms = USUnits.kilograms(pounds)
                }
                set.reps = count
                set.unitRaw = exercise.isTimed ? "seconds" : "reps"
                if set.exerciseName.isEmpty { set.exerciseName = exercise.name }
                if editing == nil { context.insert(set) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct TrainingExerciseEntryView: View {
    let workout: RoutineDay
    let editing: TrainingExercise?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var sets: Int
    @State private var repGoal: String
    @State private var selectedWorkout: RoutineDay
    @State private var error: String?

    init(workout: RoutineDay, editing: TrainingExercise? = nil) {
        self.workout = workout
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _sets = State(initialValue: editing?.plannedSets ?? 3)
        _repGoal = State(initialValue: editing?.repGoal ?? "")
        _selectedWorkout = State(initialValue: editing.flatMap { RoutineDay(rawValue: $0.workoutRaw) } ?? workout)
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !repGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Exercise name", text: $name)
                    Picker("Workout", selection: $selectedWorkout) {
                        Text("Workout A").tag(RoutineDay.trainingA)
                        Text("Workout B").tag(RoutineDay.trainingB)
                    }
                    Stepper("\(sets) planned sets", value: $sets, in: 1...10)
                    TextField("Rep goal, e.g. 8–12", text: $repGoal)
                }
                Section {
                    Text("For timed movements, include “seconds” in the goal, such as “30–45 seconds”.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }
            .dismissibleKeyboard()
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .navigationTitle(editing == nil ? "Add exercise" : "Edit exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save", action: save).disabled(!valid)
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard valid else { return }
        do {
            try DiaryStore.save(context: context) {
                let exercise = editing ?? TrainingExercise(name: name, plannedSets: sets, repGoal: repGoal, workout: selectedWorkout)
                let originalWorkout = exercise.workoutRaw
                let originalName = exercise.name
                if editing != nil {
                    let exerciseID = exercise.id.uuidString
                    let pastSets = try context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseID == exerciseID }))
                    for set in pastSets where set.exerciseName.isEmpty { set.exerciseName = originalName }
                }
                if editing == nil || originalWorkout != selectedWorkout.rawValue {
                    let destination = selectedWorkout.rawValue
                    let exercises = try context.fetch(FetchDescriptor<TrainingExercise>(predicate: #Predicate { $0.workoutRaw == destination }))
                    exercise.sortOrder = (exercises.map(\.sortOrder).max() ?? -1) + 1
                }
                exercise.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                exercise.plannedSets = sets
                exercise.repGoal = repGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                exercise.workoutRaw = selectedWorkout.rawValue
                exercise.isCalendarImported = false
                if editing == nil { context.insert(exercise) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}


/// Freeform sets use the same storage and backup format as planned workout sets.
struct CustomExerciseEntryView: View {
    let calendar: TrackingCalendar
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSet.date, order: .reverse) private var history: [WorkoutSet]
    @State private var name = ""
    @State private var load = ""
    @State private var reps = ""
    @State private var setCount = 1
    @State private var date = Date()
    @State private var logVisit = true
    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 120 &&
        NumericInput.valid(load, in: 0...2000) &&
        Int(reps).map { (1...100).contains($0) } == true && date <= Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("e.g. Dumbbell bench press", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Exercise name")
                    DatePicker("When", selection: $date, in: ...Date())
                }
                Section {
                    DecimalField(title: "Weight · lb", text: $load)
                    DecimalField(title: "Reps", text: $reps)
                    Stepper("Sets: \(setCount)", value: $setCount, in: 1...20)
                } header: { Text("What you lifted") } footer: {
                    Text("Enter 0 lb for bodyweight. Sets use the same weight and reps; log another entry if they changed.")
                }
                Section {
                    Toggle("Also log a gym visit", isOn: $logVisit)
                } footer: {
                    Text("Saved in your Exercise log. Your planned routine stays as you set it.")
                }
            }
            .dismissibleKeyboard()
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .navigationTitle("Log exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!valid)
                }
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard valid, let pounds = NumericInput.value(load), let count = Int(reps) else { return }
        let exerciseID = history.first {
            $0.sessionID == nil && $0.exerciseName.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }?.exerciseID ?? UUID().uuidString
        do {
            try DiaryStore.save(context: context) {
                for _ in 0..<setCount {
                    let set = WorkoutSet(date: date, exerciseID: exerciseID,
                                         kilograms: USUnits.kilograms(pounds), reps: count)
                    set.exerciseName = trimmedName
                    context.insert(set)
                }
                if logVisit {
                    let day = try DiaryStore.day(for: date, calendar: calendar, context: context)
                    day.gymAttended = true
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
