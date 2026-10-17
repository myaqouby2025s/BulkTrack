import SwiftUI
import SwiftData

/// Session identity, start time and rest deadline are saved, so leaving the app never loses a workout.
struct WorkoutSessionView: View {
    let session: WorkoutSession
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\TrainingExercise.sortOrder), SortDescriptor(\TrainingExercise.addedAt)]) private var allExercises: [TrainingExercise]
    @Query(sort: \WorkoutSet.date) private var allSets: [WorkoutSet]
    @State private var selectedExerciseID: String?
    @State private var editingSet: WorkoutSet?
    @State private var load = ""
    @State private var reps = ""
    @State private var error: String?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var restSeconds = 120
    @State private var feedback = 0
    private var exercises: [WorkoutExerciseSnapshot] {
        let saved = WorkoutExerciseSnapshot.decode(session.planSnapshotJSON)
        if !saved.isEmpty { return saved }
        return allExercises.filter { $0.workoutRaw == session.workoutRaw }.map {
            WorkoutExerciseSnapshot(id: $0.id.uuidString, name: $0.name,
                                    sets: $0.isCalendarImported && CalendarFitnessPlan.isFirstWeek(on: session.startedAt, calendar: calendar) ? 2 : $0.plannedSets,
                                    repGoal: $0.repGoal)
        }
    }
    private var sets: [WorkoutSet] { allSets.filter { $0.sessionID == session.id } }
    private var calendar: TrackingCalendar { profile.trackingCalendar }
    private var isComplete: Bool { session.endedAt != nil }
    private var selectedExercise: WorkoutExerciseSnapshot? {
        exercises.first { $0.id == selectedExerciseID } ?? exercises.first { loggedCount($0) < goal($0) } ?? exercises.last
    }
    private var plannedSets: Int { exercises.reduce(0) { $0 + goal($1) } }
    private var completedExercises: Int { exercises.filter { loggedCount($0) >= goal($0) }.count }
    private var validSet: Bool {
        NumericInput.valid(load, in: 0...2000) && Int(reps).map { (1...(selectedExercise?.plan.isTimed == true ? 300 : 100)).contains($0) } == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    if !isComplete {
                        restTimer
                        if let selectedExercise { setEntry(selectedExercise) }
                        else {
                            ContentUnavailableView("No exercises in this routine", systemImage: "dumbbell",
                                                   description: Text("Close this workout and add exercises in Training."))
                        }
                    }
                    exerciseList
                    if isComplete { completedSetList }
                    if !isComplete {
                        PrimaryAction(title: "Finish workout", symbol: "checkmark") { confirmFinish = true }
                            .disabled(sets.isEmpty)
                        Button("End without logging a visit", role: .destructive) { confirmDiscard = true }
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }.padding(20)
            }
            .background(AppTheme.background).foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .dismissibleKeyboard()
            .navigationTitle(RoutineDay(rawValue: session.workoutRaw)?.title ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isComplete ? "Done" : "Close") { dismiss() } }
            }
            .onAppear { selectFirstExercise() }
            .sensoryFeedback(.success, trigger: feedback)
            .sheet(item: $editingSet) { set in
                let plan = exercises.first { $0.id == set.exerciseID }?.plan ?? allExercises.first { $0.id.uuidString == set.exerciseID }?.plan ??
                    PlannedExercise(id: set.exerciseID, name: set.exerciseName.isEmpty ? "Removed exercise" : set.exerciseName,
                                    sets: 1, reps: set.unitRaw == "seconds" ? "30 seconds" : "8–12")
                WorkoutSetEntryView(exercise: plan, editing: set)
            }
            .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish and log gym visit") { finish(logVisit: true) }
            } message: {
                Text("\(sets.count) sets recorded. \(completedExercises) of \(exercises.count) exercises have all planned sets. Your sets are saved even if you finish early.")
            }
            .confirmationDialog("End this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(sets.isEmpty ? "End empty workout" : "Keep sets and end", role: .destructive) { finish(logVisit: false) }
            } message: { Text("Your sets stay saved. Gym attendance will not be changed.") }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var summary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(calendar.format(session.startedAt, style: .dateTime.weekday().month().day())).font(.headline)
                        Text(isComplete ? "Session ended" : "Workout in progress").font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                        let seconds = max(0, Int((session.endedAt ?? clock.date).timeIntervalSince(session.startedAt)))
                        Text(duration(seconds)).font(.headline.monospacedDigit()).foregroundStyle(AppTheme.accent)
                            .accessibilityLabel("Workout duration \(seconds / 60) minutes")
                    }
                }
                SoftProgress(value: Double(sets.count), goal: Double(plannedSets), color: AppTheme.accent)
                Text("\(sets.count) \(sets.count == 1 ? "set" : "sets") recorded · \(completedExercises) of \(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises") complete")
                    .font(.caption).foregroundStyle(AppTheme.secondary)
                if CalendarFitnessPlan.isFirstWeek(on: session.startedAt, calendar: calendar) && allExercises.contains(where: { $0.workoutRaw == session.workoutRaw && $0.isCalendarImported }) {
                    Text("First week: 2 working sets per exercise.").font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
        }
    }

    private var restTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            let remaining = TrainingSchedule.remainingRest(until: session.restEndsAt, now: clock.date)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(remaining > 0 ? "Rest" : "Ready for your next set", systemImage: "timer").font(.headline)
                        Spacer()
                        if remaining > 0 {
                            Text(duration(remaining)).font(.title3.bold().monospacedDigit()).foregroundStyle(AppTheme.accent)
                                .accessibilityLabel("\(remaining) seconds of rest remaining")
                        }
                    }
                    HStack {
                        Picker("Rest after each set", selection: $restSeconds) {
                            Text("60 sec").tag(60)
                            Text("90 sec").tag(90)
                            Text("2 min").tag(120)
                            Text("3 min").tag(180)
                        }.pickerStyle(.menu).labelsHidden().accessibilityLabel("Rest duration")
                        Spacer()
                        if remaining > 0 {
                            Button("+30 sec") {
                                save { session.restEndsAt = max(Date(), session.restEndsAt ?? Date()).addingTimeInterval(30) }
                            }.font(.subheadline.bold()).frame(minHeight: 44)
                            Button("Skip") { save { session.restEndsAt = nil } }.font(.subheadline.bold()).frame(minHeight: 44)
                        } else {
                            Button("Start rest") { save { session.restEndsAt = Date().addingTimeInterval(Double(restSeconds)) } }
                                .font(.subheadline.bold()).frame(minHeight: 44)
                        }
                    }
                }
            }
        }
    }

    private func setEntry(_ exercise: WorkoutExerciseSnapshot) -> some View {
        let count = loggedCount(exercise)
        let previous = previousSet(exercise)
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.name).font(.title3.bold())
                        Text(count >= goal(exercise) ? "Extra set · goal complete" : "Set \(count + 1) of \(goal(exercise)) · \(exercise.repGoal)\(exercise.plan.isTimed ? "" : " reps")")
                            .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("\((exercises.firstIndex { $0.id == exercise.id } ?? 0) + 1)/\(exercises.count)")
                        .font(.caption.bold()).foregroundStyle(AppTheme.accent).padding(8).background(AppTheme.sage, in: Capsule())
                }
                if let previous {
                    Text("Last time: \(USUnits.weight(previous.kilograms)) × \(previous.reps) \(previous.unitRaw == "seconds" ? "sec" : "reps")")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight · lb").font(.caption.bold()).foregroundStyle(AppTheme.secondary)
                        TextField("0", text: $load).keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit()).padding(14).background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Weight in pounds")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.plan.isTimed ? "Seconds" : "Reps").font(.caption.bold()).foregroundStyle(AppTheme.secondary)
                        TextField(exercise.plan.isTimed ? "30" : "8", text: $reps).keyboardType(.numberPad)
                            .font(.title2.bold().monospacedDigit()).padding(14).background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(exercise.plan.isTimed ? "Seconds" : "Repetitions")
                    }
                }
                Text("For dumbbells, enter one dumbbell’s weight. Use 0 lb for bodyweight.")
                    .font(.caption).foregroundStyle(AppTheme.secondary)
                PrimaryAction(title: "Log set", symbol: "checkmark") { logSet(exercise) }.disabled(!validSet)
                if count >= goal(exercise), let next = exercises.first(where: { loggedCount($0) < goal($0) }) {
                    Button { select(next) } label: {
                        Label("Next: \(next.name)", systemImage: "arrow.right").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                if let latest = sets.last(where: { $0.exerciseID == exercise.id }) {
                    HStack {
                        Text("Latest: \(USUnits.weight(latest.kilograms)) × \(latest.reps) \(latest.unitRaw == "seconds" ? "sec" : "reps")")
                            .font(.caption).foregroundStyle(AppTheme.secondary)
                        Spacer()
                        Button("Undo") { save { context.delete(latest); session.restEndsAt = nil } }.font(.caption.bold()).frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeading(title: isComplete ? "Routine" : "Exercises")
            ForEach(exercises) { exercise in
                Button { select(exercise) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: loggedCount(exercise) >= goal(exercise) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(loggedCount(exercise) >= goal(exercise) ? AppTheme.accent : AppTheme.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                            Text("\(loggedCount(exercise)) / \(goal(exercise)) sets").font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                        Spacer()
                        if selectedExercise?.id == exercise.id && !isComplete {
                            Text("Current").font(.caption.bold()).foregroundStyle(AppTheme.accent)
                        }
                    }.padding(16).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(PressButtonStyle()).disabled(isComplete)
            }
            if !isComplete && !sets.isEmpty {
                DisclosureGroup("Recorded sets (\(sets.count))") { completedSetList }
                    .font(.subheadline.bold()).padding(.vertical, 8)
            }
        }
    }

    private var completedSetList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isComplete { CardHeading(title: "Recorded sets") }
            ForEach(sets) { set in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.exerciseName.isEmpty ? (exercises.first { $0.id == set.exerciseID }?.name ?? "Removed exercise") : set.exerciseName)
                            .font(.subheadline.bold())
                        Text("\(USUnits.weight(set.kilograms)) × \(set.reps) \(set.unitRaw == "seconds" ? "sec" : "reps")")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Edit set", systemImage: "pencil") { editingSet = set }
                        Button("Delete set", systemImage: "trash", role: .destructive) { save { context.delete(set) } }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Options for \(set.exerciseName.isEmpty ? "recorded" : set.exerciseName) set")
                }.padding(14).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            if sets.isEmpty && isComplete {
                Text("No sets recorded.").font(.subheadline).foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private func goal(_ exercise: WorkoutExerciseSnapshot) -> Int {
        exercise.sets
    }
    private func loggedCount(_ exercise: WorkoutExerciseSnapshot) -> Int { sets.filter { $0.exerciseID == exercise.id }.count }
    private func previousSet(_ exercise: WorkoutExerciseSnapshot) -> WorkoutSet? {
        allSets.last { $0.exerciseID == exercise.id && $0.sessionID != session.id && $0.date < session.startedAt && $0.unitRaw == (exercise.isTimed ? "seconds" : "reps") }
    }
    private func selectFirstExercise() {
        if let selectedExercise { select(selectedExercise) }
    }
    private func select(_ exercise: WorkoutExerciseSnapshot) {
        KeyboardControl.dismiss()
        selectedExerciseID = exercise.id
        let prior = sets.last { $0.exerciseID == exercise.id } ?? previousSet(exercise)
        load = prior.map { USUnits.number(USUnits.pounds($0.kilograms), digits: 1) } ?? "0"
        reps = prior.map { String($0.reps) } ?? (exercise.plan.isTimed ? "30" : "8")
    }
    private func logSet(_ exercise: WorkoutExerciseSnapshot) {
        guard validSet, let pounds = NumericInput.value(load), let repetitions = Int(reps) else { return }
        KeyboardControl.dismiss()
        do {
            try DiaryStore.save(context: context) {
                let set = WorkoutSet(date: Date(), exerciseID: exercise.id,
                                     kilograms: USUnits.kilograms(pounds), reps: repetitions)
                set.unitRaw = exercise.plan.isTimed ? "seconds" : "reps"
                set.sessionID = session.id
                set.exerciseName = exercise.name
                context.insert(set)
                session.restEndsAt = Date().addingTimeInterval(Double(restSeconds))
            }
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }
    private func finish(logVisit: Bool) {
        do {
            try DiaryStore.save(context: context) {
                session.endedAt = Date()
                session.restEndsAt = nil
                if logVisit {
                    let day = try DiaryStore.day(for: session.startedAt, calendar: calendar, context: context)
                    day.gymAttended = true
                }
                if sets.isEmpty { context.delete(session) }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ changes: () throws -> Void) {
        do { try DiaryStore.save(context: context, changes: changes); feedback += 1 }
        catch { self.error = error.localizedDescription }
    }
    private func duration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
