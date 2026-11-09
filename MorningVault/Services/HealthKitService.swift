import Foundation
import HealthKit

/// HealthKit data fetcher — sleep, activity, HRV
/// Data stays on-device only
///
/// Main-actor isolated so `isAuthorized` / `lastError` are only ever touched from the main
/// thread. The HealthKit queries themselves still run on HealthKit's own queues; the
/// continuations below only suspend, so nothing heavy happens on the main thread.
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var lastError: String?

    // MARK: - Authorization

    /// Checks current authorization status without triggering a dialog.
    /// Returns true only if health data is accessible and authorized.
    func isAuthorizedForHealthData() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        // Verify read access by executing a real HealthKit query.
        // Pattern: async continuation matches the async/await pattern used elsewhere.
        return await withCheckedContinuation { continuation in
            let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: nil,
                options: .cumulativeSum
            ) { _, result, error in
                let authorized = (error == nil && result != nil)
                continuation.resume(returning: authorized)
            }
            healthStore.execute(query)
        }
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "HealthKit not available on this device"
            return false
        }

        let types: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            Self.waterType
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
            // Verify read access using the async authorization check.
            let authorized = await isAuthorizedForHealthData()
            isAuthorized = authorized
            return authorized
        } catch {
            lastError = error.localizedDescription
            isAuthorized = false
            return false
        }
    }

    // MARK: - Water

    static let waterType = HKQuantityType(.dietaryWater)

    /// True when the app may write dietary water. Never shows a sheet.
    var canWriteWater: Bool {
        HKHealthStore.isHealthDataAvailable() && healthStore.authorizationStatus(for: Self.waterType) == .sharingAuthorized
    }

    /// Asks to write (and read) dietary water. Only called when the water tracker is turned
    /// on, so the write prompt never appears for users who do not track water.
    func requestWaterShareAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: [Self.waterType], read: [Self.waterType])
            return canWriteWater
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Writes one dietary water sample and returns its UUID.
    func saveWater(ml: Int, date: Date) async throws -> UUID {
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(ml))
        let sample = HKQuantitySample(type: Self.waterType, quantity: quantity, start: date, end: date)
        try await healthStore.save(sample)
        return sample.uuid
    }

    /// Deletes a water sample the app wrote (other apps' samples cannot be deleted).
    func deleteWater(healthID: UUID) async throws {
        let predicate = HKQuery.predicateForObject(with: healthID)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: Self.waterType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            healthStore.execute(query)
        }
        guard let sample = samples.first else { return }
        try await healthStore.delete(sample)
    }

    /// Every dietary water sample on the given day, oldest first. Nil when Health is
    /// unavailable or the query fails (no read permission reads as an empty list).
    func waterSamples(on day: Date) async -> [WaterHealthSample]? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard error == nil, let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let unit = HKUnit.literUnit(with: .milli)
                continuation.resume(returning: samples.map {
                    WaterHealthSample(id: $0.uuid, ts: $0.startDate, ml: Int($0.quantity.doubleValue(for: unit).rounded()))
                })
            }
            healthStore.execute(query)
        }
    }

    /// Millilitres of water in Health on the given day, nil when unreadable.
    func waterTotal(on day: Date) async -> Int? {
        await waterSamples(on: day)?.reduce(0) { $0 + $1.ml }
    }

    // MARK: - Fetch Sleep (last night)

    func fetchLastNightSleep() async -> SleepData? {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let bedtimeWindow = calendar.date(byAdding: .hour, value: -12, to: startOfToday)!

        let predicate = HKQuery.predicateForSamples(withStart: bedtimeWindow, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                var totalInBed: TimeInterval = 0
                var totalAsleep: TimeInterval = 0
                var totalAwake: TimeInterval = 0

                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        totalInBed += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        totalAwake += duration
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                         HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        totalAsleep += duration
                    default:
                        break
                    }
                }
                // Stage samples overlap the in-bed sample; summing all of them doubled "in bed".
                // Sources that write no in-bed sample (Apple Watch) get asleep + awake instead.
                if totalInBed == 0 { totalInBed = totalAsleep + totalAwake }

                let hoursInBed = Int(totalInBed / 3600)
                let minutesInBed = Int((totalInBed.truncatingRemainder(dividingBy: 3600)) / 60)
                let hoursAsleep = Int(totalAsleep / 3600)
                let minutesAsleep = Int((totalAsleep.truncatingRemainder(dividingBy: 3600)) / 60)

                continuation.resume(returning: SleepData(
                    hoursInBed: hoursInBed,
                    minutesInBed: minutesInBed,
                    hoursAsleep: hoursAsleep,
                    minutesAsleep: minutesAsleep,
                    date: yesterday
                ))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Step Count (today)

    func fetchTodaySteps() async -> Int? {
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                guard error == nil, let sum = result?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = Int(sum.doubleValue(for: HKUnit.count()))
                continuation.resume(returning: steps)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Active Calories (today)

    func fetchTodayActiveCalories() async -> Double? {
        let calType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: calType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                guard error == nil, let sum = result?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let cals = sum.doubleValue(for: HKUnit.kilocalorie())
                continuation.resume(returning: cals)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch HRV (last reading)

    func fetchLatestHRV() async -> Double? {
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)


        // HRV is measured during sleep — look back 3 days to find the most recent sleep session
        let calendar = Calendar.current
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: threeDaysAgo, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard error == nil, let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let hrv = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: hrv)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Heart Rate (latest)

    func fetchLatestHeartRate() async -> Double? {
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard error == nil, let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let hr = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: hr)
            }
            healthStore.execute(query)
        }
    }
}


