import Foundation
import JARVISCore

#if canImport(MapKit)
import MapKit
import CoreLocation
#endif

public actor NavigationExecutor {
    public init() {}

    public func execute(intent: JARVISIntent) async throws -> ExecutionResult {
        guard let destination = intent.target ?? intent.parameters["destination"] else {
            return .failure(error: "No destination specified")
        }

        #if canImport(MapKit)
        // Geocode the destination
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(destination)

        guard let placemark = placemarks.first else {
            return .failure(error: "Could not find location: \(destination)")
        }

        let mapItem = MKMapItem(placemark: MKPlacemark(placemark: placemark))
        mapItem.name = destination

        let launchOptions: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ]

        mapItem.openInMaps(launchOptions: launchOptions)
        return .success(message: "Opening directions to \(destination)")
        #else
        return .failure(error: "MapKit not available")
        #endif
    }
}
