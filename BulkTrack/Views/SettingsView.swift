import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct DiaryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalid("The selected backup could not be read.")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct PendingBackup: Identifiable {
    let id = UUID()
    let snapshot: BackupSnapshot
}

struct SettingsView: View {
    let profile: UserProfile
    let currentWeight: Double
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health
    @State private var showProfile = false
    @State private var requestingHealth = false
    @State private var backupDocument: DiaryBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingBackup: PendingBackup?
    @State private var error: String?
    @State private var status: String?

    private var todayHealth: HealthDay? { health.days[profile.trackingCalendar.key(for: Date())] }
    private var exportName: String { "BulkTrack-\(profile.trackingCalendar.key(for: Date()))" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("BulkTrackMark").resizable().scaledToFit().frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BulkTrack").font(.title3.weight(.semibold))
                            Text("Your training, nutrition and progress.")
                                .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Section("Profile & goals") {
                    LabeledContent("Height", value: USUnits.height(profile.heightCM))
                    LabeledContent("Current weight", value: USUnits.weight(currentWeight))
                    LabeledContent("Goal weight", value: USUnits.weight(profile.targetWeightKG))
                    Button { showProfile = true } label: {
                        Label("Edit profile & daily goals", systemImage: "slider.horizontal.3")
                    }.frame(minHeight: 32)
                }
                Section {
                    LabeledContent("Availability", value: health.isAvailable ? "Available" : "Unavailable on this device")
                    LabeledContent("Health access", value: health.hasRequestedReadAccess ? "Requested" : "Not requested")
                    if let refreshed = health.lastRefresh {
                        LabeledContent("Last refresh", value: refreshed.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                    if let reading = todayHealth {
                        LabeledContent("Recorded active energy", value: energy(reading.energy.activeKcal))
                        LabeledContent("Recorded resting energy", value: energy(reading.energy.basalKcal))
                        LabeledContent("Recorded sleep", value: sleep(reading.sleepSeconds))
                    }
                    Button {
                        Task { await requestHealth() }
                    } label: {
                        HStack {
                            Label(health.hasRequestedReadAccess ? "Review Health access" : "Connect Apple Health", systemImage: "heart")
                            Spacer()
                            if requestingHealth { ProgressView().controlSize(.small) }
                        }
                    }.disabled(!health.isAvailable || requestingHealth)
                    if health.hasRequestedReadAccess {
                        Button {
                            Task { await health.refresh(calendar: profile.trackingCalendar) }
                        } label: { Label("Refresh Health readings", systemImage: "arrow.clockwise") }
                            .disabled(health.isRefreshing || requestingHealth)
                    }
                    DisclosureGroup("How Health data is used") {
                        Text("BulkTrack reads active energy, resting energy and sleep. Your calorie target estimates the whole day; Health readings describe energy recorded so far. A missing reading stays unknown rather than becoming zero.")
                        Text("Apple keeps read permission private, so a completed access request does not confirm permission. To change access, open Health → your profile → Apps → BulkTrack.")
                        Text("Weight is written to Health only when you choose to export a weigh-in. Food, water, creatine and workouts stay in your local diary.")
                    }.font(.subheadline)
                    if !health.issues.isEmpty {
                        ForEach(health.issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.circle")
                                .font(.footnote).foregroundStyle(AppTheme.peachInk)
                        }
                    }
                } header: { Text("Apple Health") } footer: {
                    Text("A refresh reads the last 14 days. Sleep combines overlapping asleep records so multiple devices do not count the same time twice.")
                }
                Section {
                    Button(action: prepareExport) {
                        Label("Export complete backup", systemImage: "square.and.arrow.up")
                    }
                    Button { showImporter = true } label: {
                        Label("Restore from backup…", systemImage: "square.and.arrow.down")
                    }
                    if let status {
                        Label(status, systemImage: "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(AppTheme.accent)
                    }
                } header: { Text("Backup & restore") } footer: {
                    Text("Save a JSON file to Files or iCloud Drive. It includes your profile, meals, habits, weights, exercises, workouts and schedule changes. A restore is reviewed before anything changes. Apple Health readings are fetched again and are not copied into the backup.")
                }
                Section("Storage & privacy") {
                    Label("Your diary works offline", systemImage: "iphone")
                    Text("Entries are stored on this iPhone with SwiftData. There is no BulkTrack account, subscription or server. Health updates need data available on your device. Keep a backup before moving to another phone or deleting the app.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                    Text("Backup files contain personal measurements and diary entries. Choose a storage location you trust.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                    LabeledContent("Diary time zone", value: profile.trackingTimeZoneID)
                        .font(.footnote)
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"))")
                        .font(.footnote)
                }
            }
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showProfile) { ProfileEditorView(profile: profile, currentKG: currentWeight) }
            .sheet(item: $pendingBackup) { pending in
                BackupReviewView(snapshot: pending.snapshot) {
                    try DataBackup.restore(pending.snapshot, context: context)
                    status = "Backup restored. Your other entries were kept."
                    pendingBackup = nil
                    Task { await health.refresh(calendar: profile.trackingCalendar) }
                }
            }
            .fileExporter(isPresented: $showExporter, document: backupDocument, contentType: .json,
                          defaultFilename: exportName) { result in
                switch result {
                case .success: status = "Backup saved."
                case .failure(let failure): showErrorUnlessCancelled(failure)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { readBackup(url) }
                case .failure(let failure): showErrorUnlessCancelled(failure)
                }
            }
            .alert("Couldn’t complete action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func energy(_ value: Double?) -> String { value.map { "\(USUnits.number($0)) Cal" } ?? "No reading" }
    private func sleep(_ seconds: Double?) -> String {
        guard let seconds else { return "No reading" }
        let minutes = Int(seconds / 60)
        return "\(minutes / 60) hr \(minutes % 60) min"
    }
    @MainActor private func requestHealth() async {
        requestingHealth = true
        defer { requestingHealth = false }
        do {
            try await health.requestReadAccess()
            await health.refresh(calendar: profile.trackingCalendar)
        } catch { self.error = error.localizedDescription }
    }
    private func prepareExport() {
        do {
            backupDocument = DiaryBackupDocument(data: try DataBackup.capture(context: context).encoded())
            showExporter = true
        } catch { self.error = error.localizedDescription }
    }
    private func readBackup(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= BackupSnapshot.maximumBytes else { throw BackupError.invalid("Choose a backup smaller than 30 MB.") }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            pendingBackup = PendingBackup(snapshot: try BackupSnapshot.decode(data))
        } catch { self.error = error.localizedDescription }
    }
    private func showErrorUnlessCancelled(_ failure: Error) {
        if (failure as NSError).code != NSUserCancelledError { error = failure.localizedDescription }
    }
}

private struct BackupReviewView: View {
    let snapshot: BackupSnapshot
    let restore: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Review this backup before restoring it.")
                        .font(.headline)
                    LabeledContent("Created", value: snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Goal weight", value: USUnits.weight(snapshot.profile.targetWeightKG))
                    LabeledContent("Diary time zone", value: snapshot.profile.trackingTimeZoneID)
                }
                Section("Contents") {
                    count("Diary days", snapshot.days.count)
                    count("Food entries", snapshot.foods.count)
                    count("Weight entries", snapshot.weights.count)
                    count("Exercises", snapshot.exercises.count)
                    count("Workout sessions", snapshot.sessions.count)
                    count("Workout sets", snapshot.sets.count)
                    count("Schedule changes", snapshot.schedule.count)
                }
                Section {
                    Text("Your profile and goals will use the values in this backup. Entries with the same ID, diary date or schedule date will be updated. Other current entries will stay saved. This can bring back entries you deleted after making the backup.")
                    Text("Restoring does not write to Apple Health. Any restored changes to an exported weigh-in can be exported again manually.")
                    Button("Restore this backup") {
                        do { try restore() } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
                } header: { Text("What will change") } footer: {
                    Text("You can cancel now without changing your diary.")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(AppTheme.peachInk)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .foregroundStyle(AppTheme.ink).tint(AppTheme.accent)
            .navigationTitle("Restore backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private func count(_ title: String, _ value: Int) -> some View {
        LabeledContent(title, value: value.formatted())
    }
}
