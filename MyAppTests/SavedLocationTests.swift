import Foundation
import Testing
@testable import MyApp

/// Checks the location saved for background weather. Made-up coordinates only.
struct SavedLocationTests {

    /// A private settings store, so tests don't touch the app's real one.
    private func emptyDefaults() throws -> UserDefaults {
        let name = "SavedLocationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func roundsToTwoDecimals() {
        let location = SavedLocation(latitude: -12.34567, longitude: 123.45432)
        #expect(location.latitude == -12.35)
        #expect(location.longitude == 123.45)
    }

    @Test func nothingSavedGivesNil() throws {
        #expect(SavedLocation.load(from: try emptyDefaults()) == nil)
    }

    @Test func saveThenLoad() throws {
        let defaults = try emptyDefaults()
        SavedLocation(latitude: 10.111, longitude: -20.229).save(to: defaults)
        #expect(SavedLocation.load(from: defaults) == SavedLocation(latitude: 10.11, longitude: -20.23))
    }

    @Test func storesOnlyRoundedValues() throws {
        let defaults = try emptyDefaults()
        SavedLocation(latitude: 1.23456, longitude: 6.54321).save(to: defaults)
        #expect(defaults.double(forKey: SavedLocation.latitudeKey) == 1.23)
        #expect(defaults.double(forKey: SavedLocation.longitudeKey) == 6.54)
    }
}
