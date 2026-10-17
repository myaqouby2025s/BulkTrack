import SwiftUI
import SwiftData

struct TrainingPlanView: View {
    let profile: UserProfile
    let now: Date
    let attended: Set<String>
    let streak: Int
    let toggleAttendance: (Date) -> Void
    let updateDate: () -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @Query(sort: [SortDescriptor(\TrainingExercise.sortOrder), SortDescriptor(\TrainingExercise.addedAt)]) private var exercises: [TrainingExercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var scheduleChanges: [WorkoutScheduleOverride]
    @State private var selectedWorkout = RoutineDay.trainingA
    @State private var sessionToShow: WorkoutSession?
    @State private var exerciseToEdit: TrainingExercise?
    @State private var exerciseToDelete: TrainingExercise?
    @State private var addingExercise = false
    @State private var loggingCustomExercise = false
    @State private var editingSchedule = false
    @State private var selectedDay: CalendarSelection?
    @State private var error: String?
    @State private var feedback = 0
    @State private var showAllHistory = false
    private var calendar: TrackingCalendar { profile.trackingCalendar }
    private var overrides: [String: RoutineDay] {
        Dictionary(scheduleChanges.compactMap { item in
            RoutineDay(rawValue: item.phaseRaw).map { (item.dayKey, $0) }
        }, uniquingKeysWith: { _, last in last })
    }
    private var phase: RoutineDay { planned(on: now) }
    private var activeSession: WorkoutSession? { sessions.first { $0.endedAt == nil } }
    private var scheduledStreak: Int {
        TrainingSchedule.streak(today: now, anchor: profile.routineAnchor, attended: attended,
                                calendar: calendar, mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
    }
    private var selectedExercises: [TrainingExercise] { exercises.filter { $0.workoutRaw == selectedWorkout.rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sessionCard
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { loggingCustomExercise = true } label: {
                            Label("Log any exercise", systemImage: "plus.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        Text("Record what you did, with your own exercise names, sets, reps and weights.")
                            .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        if sets.contains(where: { $0.sessionID == nil }) {
                            NavigationLink("Exercise log") {
                                LegacyWorkoutHistory(exercises: exercises, calendar: calendar)
                            }.font(.subheadline.bold()).frame(minHeight: 44)
                        }
                    }
                }
                routineSection
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            CardHeading(title: "Schedule", subtitle: profile.routineMode.detail)
                            Spacer()
                            Button("Edit") { editingSchedule = true }.font(.subheadline.bold()).frame(minHeight: 44)
                        }
                        GymCalendarView(calendar: calendar, anchor: profile.routineAnchor, today: now,
                                        attended: attended, mode: profile.routineMode, end: profile.routineEndDate,
                                        overrides: overrides) { selectedDay = CalendarSelection(date: $0) }
                    }
                }
                historySection
                Text("Warm up for 5–8 minutes, then do light practice sets. Keep about 2 good reps in reserve. Add the smallest available weight when all sets reach the top of your rep range with good form.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary).padding(.horizontal, 2)
            }.padding(20)
        }
        .background(AppTheme.background).navigationTitle("Training").navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear {
            let next = TrainingSchedule.nextTraining(onOrAfter: now, anchor: profile.routineAnchor, calendar: calendar,
                                                    mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
            if next.phase.isTraining { selectedWorkout = next.phase }
        }
        .sheet(item: $sessionToShow, onDismiss: updateDate) { session in
            WorkoutSessionView(session: session, profile: profile)
        }
        .sheet(item: $exerciseToEdit) { exercise in TrainingExerciseEntryView(workout: selectedWorkout, editing: exercise) }
        .sheet(isPresented: $loggingCustomExercise, onDismiss: updateDate) { CustomExerciseEntryView(calendar: calendar) }
        .sheet(isPresented: $addingExercise) { TrainingExerciseEntryView(workout: selectedWorkout) }
        .sheet(item: $selectedDay, onDismiss: updateDate) { selected in
            TrainingDayEditor(profile: profile, date: selected.date, attended: attended, overrides: overrides,
                              toggleAttendance: toggleAttendance)
        }
        .sheet(isPresented: $editingSchedule, onDismiss: updateDate) { TrainingScheduleEditor(profile: profile) }
        .confirmationDialog("Remove exercise?", isPresented: Binding(get: { exerciseToDelete != nil }, set: { if !$0 { exerciseToDelete = nil } }), titleVisibility: .visible) {
            Button("Remove from routine", role: .destructive) {
                if let exerciseToDelete {
                    save {
                        for set in sets where set.exerciseID == exerciseToDelete.id.uuidString && set.exerciseName.isEmpty {
                            set.exerciseName = exerciseToDelete.name
                        }
                        context.delete(exerciseToDelete)
                    }
                }
                exerciseToDelete = nil
            }
        } message: { Text("Previously logged sets will remain in your history.") }
        .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var sessionCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    IconBadge(symbol: activeSession == nil && !phase.isTraining ? "leaf.fill" : "dumbbell.fill",
                              color: AppTheme.accent, background: AppTheme.sage)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeSession.map { "\(RoutineDay(rawValue: $0.workoutRaw)?.title ?? "Workout") in progress" } ?? phase.title)
                            .font(.title3.bold())
                        Text(sessionSubtitle).font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                PrimaryAction(title: activeSession == nil ? "Start \(selectedWorkout.title)" : "Resume workout",
                              symbol: activeSession == nil ? "play.fill" : "arrow.right") { startOrResume() }
                    .disabled(activeSession == nil && selectedExercises.isEmpty)
                if !phase.isTraining && activeSession == nil {
                    Text("An extra workout can be logged on a recovery day. Your planned schedule stays the same.")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
                HStack {
                    Label("\(scheduledStreak) session streak", systemImage: "flame.fill")
                    Spacer()
                    if attended.contains(calendar.key(for: now)) {
                        Label("Visit logged", systemImage: "checkmark.circle.fill")
                    }
                }.font(.caption.weight(.medium)).foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private var sessionSubtitle: String {
        if let activeSession {
            return "Started \(calendar.format(activeSession.startedAt, style: .dateTime.month().day().hour().minute()))"
        }
        if phase.isTraining { return "\(exercises.filter { $0.workoutRaw == phase.rawValue }.count) exercises · weights in pounds" }
        let next = TrainingSchedule.nextTraining(onOrAfter: calendar.adding(days: 1, to: now), anchor: profile.routineAnchor,
                                                calendar: calendar, mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
        return next.phase.isTraining
            ? "Next: \(next.phase.title) · \(calendar.format(next.date, style: .dateTime.weekday().month().day()))"
            : "Extend your schedule below to plan more sessions."
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(title: "Routines", subtitle: "Adjust exercises to match your gym and equipment.")
            Picker("Workout routine", selection: $selectedWorkout) {
                Text("Workout A").tag(RoutineDay.trainingA)
                Text("Workout B").tag(RoutineDay.trainingB)
            }.pickerStyle(.segmented)
            if selectedExercises.isEmpty {
                ContentUnavailableView("No exercises", systemImage: "dumbbell", description: Text("Add an exercise to build this routine."))
                    .frame(maxWidth: .infinity)
            }
            ForEach(selectedExercises) { exercise in
                routineRow(exercise)
            }
            Button { addingExercise = true } label: {
                Label("Add exercise", systemImage: "plus.circle").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(PressButtonStyle())
        }
    }

    private func routineRow(_ exercise: TrainingExercise) -> some View {
        let previous = sets.first { $0.exerciseID == exercise.id.uuidString }
        return SurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name).font(.headline)
                    Text("\(exercise.plannedSets) sets · \(exercise.repGoal)\(exercise.plan.isTimed ? "" : " reps")")
                        .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    if let previous {
                        Text("Last: \(USUnits.weight(previous.kilograms)) × \(previous.reps) \(previous.unitRaw == "seconds" ? "sec" : "reps")")
                            .font(.caption).foregroundStyle(AppTheme.secondary)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Edit exercise", systemImage: "pencil") { exerciseToEdit = exercise }
                    Button("Move up", systemImage: "arrow.up") { move(exercise, by: -1) }
                        .disabled(selectedExercises.first?.id == exercise.id)
                    Button("Move down", systemImage: "arrow.down") { move(exercise, by: 1) }
                        .disabled(selectedExercises.last?.id == exercise.id)
                    Button("Remove from routine", systemImage: "trash", role: .destructive) { exerciseToDelete = exercise }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Options for \(exercise.name)")
            }
        }
    }

    @ViewBuilder private var historySection: some View {
        if !sessions.filter({ $0.endedAt != nil }).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeading(title: "History")
                    Spacer()
                    if sessions.filter({ $0.endedAt != nil }).count > 8 {
                        Button(showAllHistory ? "Show less" : "See all") { showAllHistory.toggle() }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                }
                ForEach(Array(sessions.filter { $0.endedAt != nil }.prefix(showAllHistory ? sessions.count : 8))) { session in
                    Button { sessionToShow = session } label: {
                        SurfaceCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(RoutineDay(rawValue: session.workoutRaw)?.title ?? "Workout").font(.headline)
                                    Text("\(calendar.format(session.startedAt, style: .dateTime.month().day())) · \(sets.filter { $0.sessionID == session.id }.count) sets")
                                        .font(.caption).foregroundStyle(AppTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold())
                            }
                        }
                    }.buttonStyle(PressButtonStyle())
                }

            }
        }
    }

    private func planned(on date: Date) -> RoutineDay {
        TrainingSchedule.phase(on: date, anchor: profile.routineAnchor, calendar: calendar,
                               mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
    }
    private func move(_ exercise: TrainingExercise, by offset: Int) {
        var ordered = selectedExercises
        guard let source = ordered.firstIndex(where: { $0.id == exercise.id }), ordered.indices.contains(source + offset) else { return }
        ordered.swapAt(source, source + offset)
        save { for (index, item) in ordered.enumerated() { item.sortOrder = index } }
    }
    private func startOrResume() {
        if let activeSession { sessionToShow = activeSession; return }
        let date = Date()
        let session = WorkoutSession(startedAt: date, workout: selectedWorkout, dayKey: calendar.key(for: date))
        do {
            try DiaryStore.save(context: context) {
                let snapshot = selectedExercises.map { exercise in
                    WorkoutExerciseSnapshot(id: exercise.id.uuidString, name: exercise.name,
                                            sets: exercise.isCalendarImported && CalendarFitnessPlan.isFirstWeek(on: date, calendar: calendar) ? 2 : exercise.plannedSets,
                                            repGoal: exercise.repGoal)
                }
                session.planSnapshotJSON = WorkoutExerciseSnapshot.encode(snapshot)
                context.insert(session)
            }
            sessionToShow = session
            feedback += 1
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ changes: () throws -> Void) {
        do { try DiaryStore.save(context: context, changes: changes); feedback += 1 }
        catch { self.error = error.localizedDescription }
    }
}

private struct CalendarSelection: Identifiable { var id: Date { date }; let date: Date }

private struct LegacyWorkoutHistory: View {
    @Query(sort: \WorkoutSet.date, order: .reverse) private var allSets: [WorkoutSet]
    private var sets: [WorkoutSet] { allSets.filter { $0.sessionID == nil } }
    let exercises: [TrainingExercise]
    let calendar: TrackingCalendar
    @Environment(\.modelContext) private var context
    @State private var selectedSet: WorkoutSet?
    @State private var error: String?
    var body: some View {
        List {
            ForEach(sets) { set in
                let exercise = exercises.first { $0.id.uuidString == set.exerciseID }
                Button { selectedSet = set } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise?.name ?? (set.exerciseName.isEmpty ? "Removed exercise" : set.exerciseName)).font(.headline).foregroundStyle(AppTheme.ink)
                        Text("\(USUnits.weight(set.kilograms)) × \(set.reps) \(set.unitRaw == "seconds" ? "sec" : "reps") · \(calendar.format(set.date, style: .dateTime.month().day()))")
                            .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }.padding(.vertical, 5)
                }.swipeActions {
                    Button("Delete", role: .destructive) {
                        do { try DiaryStore.save(context: context) { context.delete(set) } }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .navigationTitle("Exercise log").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSet) { set in
            let exercise = exercises.first { $0.id.uuidString == set.exerciseID }?.plan ??
                PlannedExercise(id: set.exerciseID, name: set.exerciseName.isEmpty ? "Removed exercise" : set.exerciseName, sets: 1, reps: set.unitRaw == "seconds" ? "30 seconds" : "8–12")
            WorkoutSetEntryView(exercise: exercise, editing: set)
        }
        .alert("Couldn’t delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
