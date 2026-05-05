import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct JourneyView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var locationManager: LocationManager

    @State private var mode: Mode = .list
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var editingEvent: LoveEvent?
    @State private var deletingEvent: LoveEvent?
    @State private var previewingEvent: LoveEvent?

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
                                
                                if let previewMedia = event.media.first {
                                    EventMediaInlinePreview(
                                        media: previewMedia,
                                        additionalImageCount: max(event.media.count - 1, 0)
                                    ) {
                                        previewingEvent = event
                                    }
                                    .accessibilityIdentifier("journey.imagePreview.open")

                                    Text(
                                        event.media.count == 1
                                            ? "Image preview"
                                            : "\(event.media.count) images attached"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Button("Edit") {
                                        editingEvent = event
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Delete", role: .destructive) {
                                        deletingEvent = event
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.top, 4)
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
        .sheet(item: $editingEvent) { event in
            JourneyEventEditor(event: event)
                .environmentObject(session)
                .environmentObject(locationManager)
        }
        .sheet(item: $previewingEvent) { event in
            EventMediaPreviewSheet(event: event)
        }
        .alert(
            "Delete Journey Item?",
            isPresented: Binding(
                get: { deletingEvent != nil },
                set: { newValue in
                    if !newValue {
                        deletingEvent = nil
                    }
                }
            ),
            presenting: deletingEvent
        ) { event in
            Button("Delete", role: .destructive) {
                Task {
                    let didDelete = await session.deleteJourneyEvent(event)
                    if didDelete {
                        deletingEvent = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                deletingEvent = nil
            }
        } message: { event in
            Text(event.note ?? "This journey item will be permanently deleted.")
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

private struct JourneyEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var locationManager: LocationManager

    let event: LoveEvent

    @State private var note: String
    @State private var locationDraft: EditableEventLocation
    @State private var locationMessage: String?
    @State private var isResolvingLocation = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImageExtension = "jpg"
    @State private var removeCurrentImage = false

    init(event: LoveEvent) {
        self.event = event
        _note = State(initialValue: event.note ?? "")
        _locationDraft = State(
            initialValue: EditableEventLocation(
                addressText: event.location.addressText ?? "",
                latitude: event.location.lat,
                longitude: event.location.lng
            )
        )
    }

    private var hasExistingImage: Bool {
        !event.media.isEmpty
    }

    private var isCurrentImageVisible: Bool {
        hasExistingImage && !removeCurrentImage && selectedImageData == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    Text(AppDisplayTime.estDateTime(event.occurredAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("journey.edit.note")
                }

                EventLocationEditorSection(
                    title: "Location",
                    draft: $locationDraft,
                    currentLocation: currentEditableLocation,
                    accessibilityPrefix: "journey.edit.location",
                    isDisabled: false,
                    statusMessage: locationMessage,
                    isResolving: isResolvingLocation
                )

                Section("Image") {
                    if isCurrentImageVisible {
                        Label("Current image attached", systemImage: "photo")
                            .foregroundStyle(.secondary)
                    }

                    if removeCurrentImage && selectedImageData == nil {
                        Label("Current image will be removed", systemImage: "trash")
                            .foregroundStyle(.red)
                    }

                    if selectedImageData != nil {
                        Label("New image selected", systemImage: "photo.badge.plus")
                            .foregroundStyle(.secondary)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Text(isCurrentImageVisible || selectedImageData != nil ? "Replace Image" : "Add Image")
                    }
                    .accessibilityIdentifier("journey.edit.image")

                    if hasExistingImage && !removeCurrentImage {
                        Button("Remove Current Image", role: .destructive) {
                            removeCurrentImage = true
                            selectedPhotoItem = nil
                            selectedImageData = nil
                            selectedImageExtension = "jpg"
                        }
                        .accessibilityIdentifier("journey.edit.removeImage")
                    }

                    if selectedImageData != nil {
                        Button("Clear New Image") {
                            selectedPhotoItem = nil
                            selectedImageData = nil
                            selectedImageExtension = "jpg"
                        }
                    }
                }
            }
            .navigationTitle("Edit Journey Item")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveJourneyEvent()
                    }
                    .disabled(session.isBusy || !locationDraft.canResolveOrSubmit || isResolvingLocation)
                    .accessibilityIdentifier("journey.edit.save")
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        if data.count > FirebaseStorageMediaService.maxAcceptedInputBytes {
                            session.globalErrorMessage = "Image is too large. Please choose a file under 20MB."
                            selectedImageData = nil
                            selectedImageExtension = "jpg"
                            return
                        }

                        let utType = newValue.supportedContentTypes.first
                        let ext = utType?.preferredFilenameExtension?.lowercased() ?? "jpg"
                        selectedImageData = data
                        selectedImageExtension = ext
                        removeCurrentImage = false
                    }
                }
            }
        }
        .onChange(of: locationDraft.addressText) { _, _ in
            locationMessage = nil
        }
    }

    private var currentEditableLocation: EditableEventLocation? {
        guard let coordinate = locationManager.coordinate else { return nil }
        return EditableEventLocation(
            addressText: locationManager.addressText ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    private func saveJourneyEvent() {
        Task { @MainActor in
            let resolvedLocation = await resolveLocationIfNeeded()
            guard let resolvedLocation else { return }

            let didSave = await session.updateJourneyEvent(
                event,
                note: note,
                location: resolvedLocation,
                imageData: selectedImageData,
                imageFileExtension: selectedImageExtension,
                removeExistingImage: removeCurrentImage || selectedImageData != nil
            )
            if didSave {
                dismiss()
            }
        }
    }

    @MainActor
    private func resolveLocationIfNeeded() async -> EventLocation? {
        locationMessage = nil

        if let location = locationDraft.eventLocation {
            return location
        }

        let query = locationDraft.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            locationMessage = AppError.invalidLocation.localizedDescription
            return nil
        }

        isResolvingLocation = true
        defer { isResolvingLocation = false }

        do {
            let resolvedLocation = try await locationManager.resolveLocationQuery(query)
            locationDraft.applyResolvedLocation(resolvedLocation, fallbackAddressText: query)
            return locationDraft.eventLocation
        } catch {
            locationMessage = AppError.invalidLocation.localizedDescription
            return nil
        }
    }
}
