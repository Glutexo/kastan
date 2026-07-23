import CoreLocation
import Foundation

/// A transport-search coordinate detached from Core Location's reference types.
struct CurrentLocationCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// Describes actionable reasons why Kaštan could not fill a journey endpoint from the Mac's location.
enum CurrentLocationError: Error, Equatable {
    case servicesDisabled
    case permissionDenied
    case unavailable
    case requestInProgress
}

/// Supplies one current WGS-84 coordinate when the user explicitly requests it.
@MainActor
protocol CurrentLocationProviding {
    func currentLocation() async throws -> CurrentLocationCoordinate
}

/// Requests Core Location only for an explicit `Here` button action and stops after one result.
@MainActor
final class SystemCurrentLocationProvider: NSObject, CurrentLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CurrentLocationCoordinate, Error>?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CurrentLocationCoordinate {
        guard continuation == nil else {
            throw CurrentLocationError.requestInProgress
        }
        guard CLLocationManager.locationServicesEnabled() else {
            throw CurrentLocationError.servicesDisabled
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            continueRequest(for: manager.authorizationStatus)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        continueRequest(for: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(CurrentLocationError.unavailable))
            return
        }

        finish(with: .success(CurrentLocationCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(CurrentLocationError.unavailable))
    }

    private func continueRequest(for authorizationStatus: CLAuthorizationStatus) {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(with: .failure(CurrentLocationError.permissionDenied))
        @unknown default:
            finish(with: .failure(CurrentLocationError.unavailable))
        }
    }

    private func finish(with result: Result<CurrentLocationCoordinate, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

/// Gives location failures concise localized guidance instead of exposing Core Location internals.
enum CurrentLocationErrorPresentation {
    static func message(for error: Error) -> String {
        switch error as? CurrentLocationError {
        case .servicesDisabled:
            AppLocalization.string(
                "Location Services are turned off. Enable them in System Settings to use My location."
            )
        case .permissionDenied:
            AppLocalization.string(
                "Location access was denied. Allow Kaštan to use your location in System Settings."
            )
        case .requestInProgress:
            AppLocalization.string("Kaštan is already determining your current location.")
        case .unavailable, nil:
            AppLocalization.string("Your current location could not be determined. Try again.")
        }
    }
}
