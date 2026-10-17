import SwiftUI
import SwiftData

@main
struct BulkTrackApp: App {
    private let storage: Result<ModelContainer, Error> = Result {
        let schema = Schema([UserProfile.self, DailyLog.self, FoodEntry.self, WeightEntry.self,
                             WorkoutSet.self, TrainingExercise.self, WorkoutSession.self,
                             WorkoutScheduleOverride.self])
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            // UI tests use an isolated in-memory diary and never open the user's store.
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
            let context = container.mainContext
            let calendar = TrackingCalendar(timeZoneID: "America/New_York")
            let profile = UserProfile(heightCM: 175, initialWeightKG: USUnits.kilograms(150), targetWeightKG: USUnits.kilograms(170),
                                      birthDate: calendar.adding(days: -25 * 365, to: Date()), equation: .male,
                                      routineAnchor: calendar.start(of: Date()), trackingTimeZoneID: "America/New_York")
            profile.calendarPlanVersion = 1
            context.insert(profile)
            context.insert(TrainingExercise(name: "Leg press", plannedSets: 2, repGoal: "8–12", workout: .trainingA))
            context.insert(TrainingExercise(name: "Cable row", plannedSets: 2, repGoal: "8–12", workout: .trainingB))
            try context.save()
            return container
        }
        #endif
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
    @State private var health = HealthKitManager()
    private var testColorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-dark") { return .dark }
        #endif
        return nil
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                RootView()
                    .modelContainer(container)
                    .environment(health)
                    .tint(AppTheme.accent)
                    .preferredColorScheme(testColorScheme)
            case .failure(let error):
                ContentUnavailableView("Couldn’t open your diary", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error.localizedDescription))
            }
        }
    }
}

private struct RootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @State private var planError: String?

    var body: some View {
        if let profile = profiles.first {
            DashboardView(profile: profile)
                .environment(\.calendar, profile.trackingCalendar.calendar)
                .environment(\.timeZone, profile.trackingCalendar.calendar.timeZone)
                .task {
                    do { try DiaryStore.installCalendarPlan(profile: profile, context: context) }
                    catch { planError = error.localizedDescription }
                }
                .alert("Couldn’t load your calendar plan", isPresented: Binding(get: { planError != nil }, set: { if !$0 { planError = nil } })) {
                    Button("OK") { planError = nil }
                } message: { Text(planError ?? "") }
        } else {
            ProfileEditorView(profile: nil)
        }
    }
}
