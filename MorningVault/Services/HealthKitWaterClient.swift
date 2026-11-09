import Foundation
import HealthKit

/// The `WaterHealthClient` the app hands to `WaterStore`: every call hops to the main-actor
/// `HealthKitService`, whose queries run on HealthKit's own queues. The widget extension
/// never creates one, so its logs stay local until the app syncs them.
struct HealthKitWaterClient: WaterHealthClient {
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestShareAuthorization() async -> Bool {
        await HealthKitService.shared.requestWaterShareAuthorization()
    }

    func canWrite() async -> Bool {
        await HealthKitService.shared.canWriteWater
    }

    func save(ml: Int, date: Date) async throws -> UUID {
        try await HealthKitService.shared.saveWater(ml: ml, date: date)
    }

    func delete(healthID: UUID) async throws {
        try await HealthKitService.shared.deleteWater(healthID: healthID)
    }

    func samples(on day: Date) async -> [WaterHealthSample]? {
        await HealthKitService.shared.waterSamples(on: day)
    }
}
