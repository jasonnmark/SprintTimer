import Foundation
import CoreLocation
import MapKit
import os

private let logger = Logger(subsystem: "com.JasonMark.SprintTimer", category: "LocationResolver")

enum LocationResolver {
    /// Reverse-geocode a coordinate into a human-readable location name.
    /// Returns nil on invalid coordinates, network failure, throttling, or empty results.
    /// Falls back from full address → city + context → city alone before giving up.
    static func reverseGeocode(location: CLLocation) async -> String? {
        let coord = location.coordinate
        guard CLLocationCoordinate2DIsValid(coord),
              !(coord.latitude == 0 && coord.longitude == 0) else {
            logger.error("reverseGeocode skipped: invalid coordinate (\(coord.latitude), \(coord.longitude))")
            return nil
        }

        logger.info("Reverse geocoding for: \(coord.latitude), \(coord.longitude)")

        guard let request = MKReverseGeocodingRequest(location: location) else {
            logger.error("MKReverseGeocodingRequest init returned nil")
            return nil
        }
        do {
            let mapItems = try await request.mapItems
            logger.info("Geocoding returned \(mapItems.count) items")
            if let item = mapItems.first {
                if let address = item.address {
                    let name = address.shortAddress ?? address.fullAddress
                    if !name.isEmpty {
                        return name
                    }
                }
                if let reps = item.addressRepresentations {
                    if let cityCtx = reps.cityWithContext {
                        return cityCtx
                    } else if let city = reps.cityName {
                        return city
                    }
                }
            }
        } catch {
            logger.error("Reverse geocoding failed: \(error)")
            return nil
        }
        logger.error("Reverse geocoding returned no usable result")
        return nil
    }
}
