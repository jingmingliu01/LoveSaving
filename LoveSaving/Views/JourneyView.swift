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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.events) { event in
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 12)

                            Divider()
                        }
                    }
                    .accessibilityIdentifier("journey.list")
                }
                .refreshable {
                    await refreshJourneyAndCamera()
                }
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
                .frame(minHeight: 420)
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                    MapScaleView()
                }
                .accessibilityIdentifier("journey.map")
                .refreshable {
                    await refreshJourneyAndCamera()
                }
            }
        }
        .navigationTitle("Journey")
        .safeAreaInset(edge: .top) {
            RefreshStatusView(state: session.refreshState(for: .journey))
        }
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
        .task(id: session.group?.id) {
            await refreshJourneyAndCamera()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .map {
                locationManager.requestAuthorizationIfNeeded()
            }
        }
    }

    private func refreshJourneyAndCamera() async {
        await session.refreshJourney()
        updateCameraPositionFromFirstEvent()
    }

    private func updateCameraPositionFromFirstEvent() {
        guard let first = session.events.first else { return }

        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: first.location.lat, longitude: first.location.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )
        )
    }
}
