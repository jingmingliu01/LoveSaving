import CoreLocation
import MapKit
import SwiftUI

struct JourneyView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var locationManager: LocationManager

    @State private var mode: Mode = .list
    @State private var cameraPosition: MapCameraPosition = .automatic

    enum Mode: String, CaseIterable, Identifiable {
        case list = "List"
        case map = "Map"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch mode {
            case .list:
                List(session.events) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.note ?? "No note")
                            .font(.headline)

                        Text(AppDisplayTime.estDateTime(event.occurredAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let address = event.location.addressText {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(event.delta >= 0 ? "+\(event.delta)" : "\(event.delta)")
                            .foregroundStyle(event.delta >= 0 ? .green : .red)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("journey.list")
            case .map:
                Map(position: $cameraPosition) {
                    ForEach(session.events) { event in
                        Marker(
                            event.note ?? "Event",
                            coordinate: CLLocationCoordinate2D(
                                latitude: event.location.lat,
                                longitude: event.location.lng
                            )
                        )
                    }
                }
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                    MapScaleView()
                }
                .accessibilityIdentifier("journey.map")
            }
        }
        .navigationTitle("Journey")
        .safeAreaInset(edge: .bottom) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("journey.modePicker")
        }
        .task {
            await session.refreshEvents()
            if let first = session.events.first {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: first.location.lat, longitude: first.location.lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                    )
                )
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .map {
                locationManager.requestAuthorizationIfNeeded()
            }
        }
    }
}
