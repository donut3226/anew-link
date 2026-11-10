import Foundation
import HealthKit
import Observation

/// Saves band steps, heart rate and VO2 Max to Apple Health. Write-only: it never reads Health data.
@Observable
final class HealthSync {

    enum Status: Equatable {
        case idle
        case asking   // waiting for the Health permission popup
        case saving
        /// `notAllowed` counts records skipped because that type wasn't allowed in the popup.
        case done(steps: Int, heartRates: Int, notAllowed: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle

    @ObservationIgnored private let store = HKHealthStore()

    private static let stepType = HKQuantityType(.stepCount)
    private static let heartRateType = HKQuantityType(.heartRate)
    private static let vo2MaxType = HKQuantityType(.vo2Max)

    var isBusy: Bool {
        status == .asking || status == .saving
    }

    /// True if saving steps is already allowed, so saving won't show the Health popup.
    /// Automatic saves only run when this is true.
    var canSaveWithoutAsking: Bool {
        HKHealthStore.isHealthDataAvailable()
            && store.authorizationStatus(for: Self.stepType) == .sharingAuthorized
    }

    /// Returns true if the save worked (or there was nothing to save).
    ///
    /// It also works with the iPhone locked: Health keeps the new data and stores it once
    /// the phone is unlocked (Apple's documented behaviour for writing while locked).
    ///
    /// - Parameters:
    ///   - samples: from the last activity sync.
    ///   - firmware: the band's firmware name, stored with each sample so Health shows which device it came from.
    ///   - askPermission: false for automatic saves, which must never show a popup.
    @discardableResult
    func save(_ samples: [ActivitySample], firmware: String?, askPermission: Bool = true) async -> Bool {
        guard !isBusy else { return false }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .failed("Apple Health isn't available on this device.")
            return false
        }
        let records = HealthRecords.make(from: samples)
        guard !records.isEmpty else {
            status = .done(steps: 0, heartRates: 0, notAllowed: 0)
            return true
        }

        do {
            if askPermission {
                status = .asking
                // Shows the Health popup the first time. "read: []" because we never read.
                try await store.requestAuthorization(toShare: [Self.stepType, Self.heartRateType, Self.vo2MaxType], read: [])
            }

            let allowed = records.filter { store.authorizationStatus(for: Self.type(for: $0.kind)) == .sharingAuthorized }
            guard !allowed.isEmpty else {
                status = .failed("Anew Link isn't allowed to save to Health. Turn it on in Health > Profile > Apps > Anew Link.")
                return false
            }

            status = .saving
            let device = HKDevice(name: "Wena 3", manufacturer: "Sony", model: WenaGATT.advertisedName,
                                  hardwareVersion: nil, firmwareVersion: firmware, softwareVersion: nil,
                                  localIdentifier: nil, udiDeviceIdentifier: nil)
            try await store.save(allowed.map { Self.sample(for: $0, device: device) })

            status = .done(steps: allowed.filter { $0.kind == .steps }.count,
                           heartRates: allowed.filter { $0.kind == .heartRate }.count,
                           notAllowed: records.count - allowed.count)
            return true
        } catch {
            status = .failed("Couldn't save to Health. \(error.localizedDescription)")
            return false
        }
    }

    private static func type(for kind: HealthRecord.Kind) -> HKQuantityType {
        switch kind {
        case .steps: stepType
        case .heartRate: heartRateType
        case .vo2Max: vo2MaxType
        }
    }

    /// Turns our plain record into a HealthKit sample.
    private static func sample(for record: HealthRecord, device: HKDevice) -> HKQuantitySample {
        let unit: HKUnit = switch record.kind {
        case .steps: .count()
        case .heartRate: .count().unitDivided(by: .minute())   // beats per minute
        case .vo2Max: HKUnit(from: "ml/kg*min")
        }
        return HKQuantitySample(
            type: type(for: record.kind),
            quantity: HKQuantity(unit: unit, doubleValue: record.value),
            start: record.start,
            end: record.end,
            device: device,
            // The sync identifier and version make Health replace a minute instead of duplicating it.
            metadata: [
                HKMetadataKeySyncIdentifier: record.syncIdentifier,
                HKMetadataKeySyncVersion: record.syncVersion,
            ]
        )
    }
}
