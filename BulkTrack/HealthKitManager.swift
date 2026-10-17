import Foundation
import HealthKit
import Observation

struct HealthDay: Sendable {
    var energy: EnergyReading
    var sleepSeconds: Double?
}

private struct HealthRead<Value: Sendable>: Sendable {
    var value: Value
    var issue: String?
}

enum HealthAccessError: LocalizedError {
    case unavailable, weightWriteNotAllowed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device."
        case .weightWriteNotAllowed: "Weight writing is not allowed. You can change access in Apple Health. Your weight remains saved in BulkTrack."
        }
    }
}

@MainActor
@Observable
final class HealthKitManager {
    private(set) var days: [String: HealthDay] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var issues: [String] = []
    private(set) var revision = 0
    // This means the permission request finished, NOT that read permission was granted.
    private(set) var hasRequestedReadAccess = UserDefaults.standard.bool(forKey: "health.read.requested.v1")

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var observers: [HKObserverQuery] = []
    @ObservationIgnored private var refreshAgain = false

    var isAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return false }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
         HKCategoryType(.sleepAnalysis)]
    }

    func requestReadAccess() async throws {
        guard isAvailable else { throw HealthAccessError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        hasRequestedReadAccess = true
        UserDefaults.standard.set(true, forKey: "health.read.requested.v1")
        startObserving()
    }

    /// Writes only explicitly selected local weights. Never writes burned energy or sleep estimates.
    /// A stable sync ID makes retrying the same entry safe if local export bookkeeping fails.
    func exportWeight(id: UUID, kilograms: Double, date: Date, version: Int = 1) async throws {
        guard isAvailable else { throw HealthAccessError.unavailable }
        let type = HKQuantityType(.bodyMass)
        try await store.requestAuthorization(toShare: [type], read: [])
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            throw HealthAccessError.weightWriteNotAllowed
        }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo),
                                                                        doubleValue: kilograms),
                                      start: date, end: date, metadata: [
                                        HKMetadataKeySyncIdentifier: "BulkTrack.weight.\(id.uuidString)",
                                        HKMetadataKeySyncVersion: max(1, version),
                                        HKMetadataKeyWasUserEntered: true
                                      ])
        try await store.save(sample)
    }

    /// Observers run while the UI is active. Foreground refresh also catches deletions/revocations.
    /// No background-delivery entitlement or background execution is claimed by this starter.
    func startObserving() {
        guard isAvailable, hasRequestedReadAccess, observers.isEmpty else { return }
        for type in readTypes.compactMap({ $0 as? HKSampleType }) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                // Only enqueue an invalidation; there is no background processing to await here.
                Task { @MainActor [weak self] in
                    if let error { self?.issues = [error.localizedDescription] }
                    self?.revision += 1
                }
                completion()
            }
            observers.append(query)
            store.execute(query)
        }
    }

    func stopObserving() {
        observers.forEach(store.stop)
        observers.removeAll()
    }

    func refresh(calendar: TrackingCalendar) async {
        guard isAvailable, hasRequestedReadAccess else { return }
        if isRefreshing { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            let now = Date()
            let dates = calendar.days(endingOn: now, count: 14)
            let start = dates[0]
            async let active = readEnergy(.activeEnergyBurned, start: start, end: now, calendar: calendar)
            async let basal = readEnergy(.basalEnergyBurned, start: start, end: now, calendar: calendar)
            async let sleep = readSleep(start: calendar.adding(days: -1, to: start), end: now)
            let (activeResult, basalResult, sleepResult) = await (active, basal, sleep)
            guard !Task.isCancelled else { return }
            var replacement: [String: HealthDay] = [:]
            for date in dates {
                let key = calendar.key(for: date)
                let seconds = calendar.sleepWindow(endingOn: date, now: now).flatMap {
                    SleepIntervals.total(sleepResult.value, within: $0)
                }
                replacement[key] = HealthDay(energy: EnergyReading(activeKcal: activeResult.value[key],
                                                                   basalKcal: basalResult.value[key]),
                                             sleepSeconds: seconds)
            }
            // Replace, don't accumulate. Removed samples or newly unavailable data clear old values.
            days = replacement
            issues = [activeResult.issue, basalResult.issue, sleepResult.issue].compactMap { $0 }
            lastRefresh = now
        } while refreshAgain && !Task.isCancelled
    }

    private func readEnergy(_ identifier: HKQuantityTypeIdentifier, start: Date, end: Date,
                            calendar: TrackingCalendar) async -> HealthRead<[String: Double]> {
        do {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let samplePredicate = HKSamplePredicate.quantitySample(type: HKQuantityType(identifier),
                                                                   predicate: predicate)
            var interval = DateComponents(day: 1)
            interval.calendar = calendar.calendar
            interval.timeZone = calendar.calendar.timeZone
            let query = HKStatisticsCollectionQueryDescriptor(predicate: samplePredicate,
                                                               options: .cumulativeSum,
                                                               anchorDate: start,
                                                               intervalComponents: interval)
            let collection = try await query.result(for: store)
            var values: [String: Double] = [:]
            // Use HealthKit's cumulative statistics; don't manually add totals from each source.
            collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                if let sum = statistics.sumQuantity() {
                    values[calendar.key(for: statistics.startDate)] = max(0, sum.doubleValue(for: .kilocalorie()))
                }
            }
            return HealthRead(value: values)
        } catch {
            if (error as? HKError)?.code == .errorNoData { return HealthRead(value: [:]) }
            let name = identifier == .activeEnergyBurned ? "Active energy" : "Resting energy"
            return HealthRead(value: [:], issue: "\(name): \(error.localizedDescription)")
        }
    }

    private func readSleep(start: Date, end: Date) async -> HealthRead<[DateInterval]> {
        do {
            // Overlap predicate, not strictStartDate: include sleep beginning before the window.
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKSampleQueryDescriptor(predicates: [
                .categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)
            ], sortDescriptors: [SortDescriptor(\HKCategorySample.startDate, order: .forward)])
            let samples = try await query.result(for: store)
            let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                         HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            let intervals = samples.compactMap { sample -> DateInterval? in
                guard asleepValues.contains(sample.value), sample.endDate > sample.startDate else { return nil }
                return DateInterval(start: sample.startDate, end: sample.endDate)
            }
            return HealthRead(value: intervals)
        } catch {
            if (error as? HKError)?.code == .errorNoData { return HealthRead(value: []) }
            return HealthRead(value: [], issue: "Sleep: \(error.localizedDescription)")
        }
    }
}
