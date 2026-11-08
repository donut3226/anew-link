import CoreLocation

/// Gets the iPhone's approximate location once, for the weather forecast.
///
/// CoreLocation, like CoreBluetooth, reports back through a delegate.
/// A "continuation" lets us turn that callback into something we can `await`.
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    enum LocationError: LocalizedError {
        case denied
        case failed

        var errorDescription: String? {
            switch self {
            case .denied: "Location permission is off. Turn it on in Settings > Privacy & Security > Location Services > Buckle Link."
            case .failed: "Couldn't find your location. Try again in a moment."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        // Kilometre accuracy is plenty for weather, and is quicker and kinder to the battery.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Asks for permission if needed, then returns one location.
    func currentLocation() async throws -> CLLocation {
        // Only one request at a time.
        if continuation != nil { throw LocationError.failed }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // Continues in locationManagerDidChangeAuthorization.
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break // Still waiting for the user to answer the popup.
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            finish(.success(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(LocationError.failed))
    }
}
