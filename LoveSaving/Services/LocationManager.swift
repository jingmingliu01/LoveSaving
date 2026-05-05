import CoreLocation
import Foundation
import Combine
import MapKit

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var addressText: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let isUITestMode: Bool

    init(isUITestMode: Bool = false) {
        self.isUITestMode = isUITestMode
        super.init()
        guard !isUITestMode else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorizationIfNeeded() {
        guard !isUITestMode else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func setMockLocationForUITests(
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        addressText: String = "San Francisco, CA"
    ) {
        self.coordinate = coordinate
        self.addressText = addressText
    }

    func resolveLocationQuery(_ query: String) async throws -> EventLocation {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw AppError.invalidLocation
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 25_000,
                longitudinalMeters: 25_000
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        guard let mapItem = response.mapItems.first else {
            throw AppError.invalidLocation
        }

        let resolvedCoordinate = mapItem.placemark.coordinate
        guard resolvedCoordinate.latitude.isFinite,
              resolvedCoordinate.longitude.isFinite else {
            throw AppError.invalidLocation
        }

        return EventLocation(
            lat: resolvedCoordinate.latitude,
            lng: resolvedCoordinate.longitude,
            addressText: resolvedAddressText(
                from: mapItem.placemark,
                fallback: mapItem.name ?? trimmedQuery
            )
        )
    }

    private func resolvedAddressText(from placemark: MKPlacemark, fallback: String) -> String {
        let pieces = [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let uniquePieces = pieces.reduce(into: [String]()) { partialResult, piece in
            guard !partialResult.contains(piece) else { return }
            partialResult.append(piece)
        }

        return uniquePieces.isEmpty ? fallback : uniquePieces.joined(separator: ", ")
    }
}

extension LocationManager: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !isUITestMode else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            coordinate = nil
            addressText = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isUITestMode else { return }
        guard let location = locations.last else { return }
        coordinate = location.coordinate

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let placemark = placemarks?.first else { return }
            let pieces = [
                placemark.name,
                placemark.locality,
                placemark.administrativeArea,
                placemark.postalCode
            ]
            let resolved = pieces
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            Task { @MainActor in
                self.addressText = resolved
            }
        }
    }
}
