import Foundation
import HealthKit

/// HealthKit data fetcher — sleep, activity, HRV
/// Data stays on-device only
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var lastError: String?

    // MARK: - Authorization

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
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
            await MainActor.run { isAuthorized = true }
            return true
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
            return false
        }
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

                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    totalInBed += duration
                    if sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        totalAsleep += duration
                    }
                }

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

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: nil,
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


