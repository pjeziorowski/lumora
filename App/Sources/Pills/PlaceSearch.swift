// App/Sources/Pills/PlaceSearch.swift
//
// Place search (MapKit), reverse geocoding (time zone and name for a coordinate) and a
// one-shot current-location fix. Every function is nonisolated and converts Apple's
// objects into Sendable `PillLocation`s before returning, so nothing non-Sendable crosses
// an actor boundary.

import CoreLocation
import GeoCore
import MapKit
import PlannerKit

enum PlaceSearch {
    enum Failure: LocalizedError {
        case locationDenied
        case locationTimedOut

        var errorDescription: String? {
            switch self {
            case .locationDenied:
                String(localized: "Location access is off. Allow it in Settings, or search for a place instead.")
            case .locationTimedOut:
                String(localized: "Couldn't get a location fix. Try again outdoors, or search for a place.")
            }
        }
    }

    /// Places and addresses matching `query`.
    static func search(_ query: String) async throws -> [PillLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            let coordinate = item.placemark.coordinate
            let name = item.name ?? item.placemark.locality
                ?? Formatting.coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude, style: .decimal)
            return PillLocation(
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                elevation: 0,
                timeZoneIdentifier: item.timeZone?.identifier
                    ?? PillLocation.nauticalTimeZone(longitude: coordinate.longitude).identifier
            )
        }
    }

    /// Names a coordinate and finds its time zone. Falls back to the coordinates and a
    /// longitude-based zone when offline or over the sea.
    static func resolve(latitude: Double, longitude: Double, elevation: Double, name: String? = nil) async -> PillLocation {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        let placemark = placemarks?.first
        return PillLocation(
            name: name ?? placemark?.locality ?? placemark?.name
                ?? Formatting.coordinate(latitude: latitude, longitude: longitude, style: .decimal),
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            timeZoneIdentifier: placemark?.timeZone?.identifier
                ?? PillLocation.nauticalTimeZone(longitude: longitude).identifier
        )
    }

    /// Name and time zone for a dropped Planner pin; nil when offline or over the sea.
    /// PlannerKit caches the result per ~1 km cell.
    static func placeInfo(latitude: Double, longitude: Double) async -> PlaceInfo? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return PlaceInfo(name: placemark.locality ?? placemark.name ?? placemark.administrativeArea,
                         timeZoneIdentifier: placemark.timeZone?.identifier)
    }

    /// One location fix, asking for permission if needed. Gives up after `timeout` seconds.
    static func currentLocation(timeout: Double = 20) async throws -> PillLocation {
        let status = await MainActor.run { () -> CLAuthorizationStatus in
            let status = LocationPermission.shared.manager.authorizationStatus
            if status == .notDetermined { LocationPermission.shared.manager.requestWhenInUseAuthorization() }
            return status
        }
        if status == .denied || status == .restricted { throw Failure.locationDenied }

        let fix = try await withThrowingTaskGroup(of: Fix?.self) { group in
            group.addTask { try await firstFix() }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let fix else {
            let denied = await MainActor.run {
                let s = LocationPermission.shared.manager.authorizationStatus
                return s == .denied || s == .restricted
            }
            throw denied ? Failure.locationDenied : Failure.locationTimedOut
        }
        return await resolve(latitude: fix.latitude, longitude: fix.longitude, elevation: max(0, fix.altitude))
    }

    private struct Fix: Sendable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
    }

    private static func firstFix() async throws -> Fix? {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return Fix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                           altitude: location.verticalAccuracy >= 0 ? location.altitude : 0)
            }
        }
        return nil
    }
}

/// Holds the CLLocationManager used to ask for permission (it must outlive the request).
@MainActor
final class LocationPermission {
    static let shared = LocationPermission()
    let manager = CLLocationManager()
}
