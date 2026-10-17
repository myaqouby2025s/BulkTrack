import SwiftUI
import SwiftData

struct TrainingDayEditor: View {
    let profile: UserProfile
    let date: Date
    let attended: Set<String>
    let overrides: [String: RoutineDay]
    let toggleAttendance: (Date) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var changes: [WorkoutScheduleOverride]
    @State private var phase = RoutineDay.rest
    @State private var destination = Date()
    @State private var error: String?
    @State private var showMove = false
    private var calendar: TrackingCalendar { profile.trackingCalendar }
    private var isLogged: Bool { attended.contains(calendar.key(for: date)) }
    private var isFuture: Bool { calendar.start(of: date) > calendar.start(of: Date()) }
    private var originalPhase: RoutineDay {
        TrainingSchedule.phase(on: date, anchor: profile.routineAnchor, calendar: calendar,
                               mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Planned session", selection: $phase) {
                        Text("Workout A").tag(RoutineDay.trainingA)
                        Text("Workout B").tag(RoutineDay.trainingB)
                        Text("Rest").tag(RoutineDay.rest)
                    }
                    Button("Save day plan") {
                        save { setOverride(date: date, phase: phase) }
                    }
                    if overrides[calendar.key(for: date)] != nil {
                        Button("Use regular schedule") {
                            save { changes.filter { $0.dayKey == calendar.key(for: date) }.forEach { context.delete($0) } }
                        }
                    }
                } header: { Text("Plan") } footer: {
                    Text("This changes your plan for this day only. Recorded workouts and attendance stay saved.")
                }
                if originalPhase.isTraining {
                    Section {
                        Toggle("Move or swap this session", isOn: $showMove)
                        if showMove {
                            DatePicker("Other day", selection: $destination, displayedComponents: .date)
                            if destinationPhase.isTraining {
                                Text("This day already has \(destinationPhase.title). Swap the sessions to keep both.")
                                    .font(.caption).foregroundStyle(AppTheme.secondary)
                            }
                            Button("Move to this day") { move(swap: false) }.disabled(!canMove || destinationPhase.isTraining)
                            Button("Swap the two days") { move(swap: true) }.disabled(!canMove)
                        }
                    } footer: {
                        if showMove {
                            Text("Move sets this day to rest and places \(originalPhase.title) on the other day. Swap exchanges their plans. Attendance always stays on the day you actually trained.")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Gym visit")
                        Spacer()
                        Text(isLogged ? "Logged" : "Not logged").foregroundStyle(isLogged ? AppTheme.accent : AppTheme.secondary)
                    }
                    if !isFuture {
                        Button(isLogged ? "Remove gym check-in" : "Log gym visit") {
                            toggleAttendance(date)
                            dismiss()
                        }
                    }
                } header: { Text("Actual attendance") } footer: {
                    Text(isFuture ? "Future days can be planned, but cannot be marked attended." : "A gym check-in records attendance without creating a guided workout or sets.")
                }
            }
            .scrollContentBackground(.hidden).background(AppTheme.background).tint(AppTheme.accent)
            .navigationTitle(calendar.format(date, style: .dateTime.weekday().month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                phase = originalPhase.isTraining ? originalPhase : .rest
                destination = calendar.adding(days: 1, to: date)
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private var destinationPhase: RoutineDay {
        TrainingSchedule.phase(on: destination, anchor: profile.routineAnchor, calendar: calendar,
                               mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
    }
    private var canMove: Bool { calendar.key(for: destination) != calendar.key(for: date) }
    private func move(swap: Bool) {
        guard canMove else { return }
        let other = TrainingSchedule.phase(on: destination, anchor: profile.routineAnchor, calendar: calendar,
                                           mode: profile.routineMode, end: profile.routineEndDate, overrides: overrides)
        save {
            setOverride(date: date, phase: swap && other.isTraining ? other : .rest)
            setOverride(date: destination, phase: originalPhase)
        }
    }
    private func setOverride(date: Date, phase: RoutineDay) {
        let key = calendar.key(for: date)
        if let existing = changes.first(where: { $0.dayKey == key }) {
            existing.phaseRaw = phase.rawValue
        } else {
            context.insert(WorkoutScheduleOverride(date: date, phase: phase, calendar: calendar))
        }
    }
    private func save(_ block: () throws -> Void) {
        do { try DiaryStore.save(context: context, changes: block); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct TrainingScheduleEditor: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mode = RoutineMode.threeDayFullBody
    @State private var anchor = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var error: String?
    private var calendar: TrackingCalendar { profile.trackingCalendar }
    private var valid: Bool { !hasEnd || calendar.start(of: end) >= calendar.start(of: anchor) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Rhythm", selection: $mode) {
                        ForEach(RoutineMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    DatePicker("First Workout A", selection: $anchor, displayedComponents: .date)
                } footer: {
                    Text(mode == .threeDayFullBody
                         ? "The first Monday, Wednesday, or Friday on or after your start date is Workout A. A and B then alternate."
                         : "Workout A, Workout B, rest, then repeat from your start date.")
                }
                Section {
                    Toggle("Set an end date", isOn: $hasEnd)
                    if hasEnd { DatePicker("Last plan day", selection: $end, displayedComponents: .date) }
                    Button("Extend by 4 weeks") {
                        hasEnd = true
                        end = calendar.adding(days: 28, to: max(end, Date()))
                    }
                } footer: {
                    Text(hasEnd ? "Training is planned through the end date. Individual calendar changes still apply." : "Your routine continues until you choose to change it.")
                }
                Section {
                    Text("Changing the regular rhythm also changes past planned days and their streak calculation. Logged visits, workout sets, and individual day overrides remain saved.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(AppTheme.background).tint(AppTheme.accent)
            .navigationTitle("Training schedule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try DiaryStore.save(context: context) {
                                profile.routineModeRaw = mode.rawValue
                                profile.routineAnchor = calendar.start(of: anchor)
                                profile.routineEndDate = hasEnd ? calendar.start(of: end) : nil
                            }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold).disabled(!valid)
                }
            }
            .onAppear {
                mode = profile.routineMode
                anchor = profile.routineAnchor
                hasEnd = profile.routineEndDate != nil
                end = profile.routineEndDate ?? calendar.adding(days: 28, to: Date())
            }
            .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
