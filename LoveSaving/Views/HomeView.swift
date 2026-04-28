import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var locationManager: LocationManager

    @StateObject private var viewModel: HomeViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var composerLocation = EditableEventLocation()
    @State private var tapFeedbackState = HomeTapFeedbackState.rest
    @State private var tapFeedbackTask: Task<Void, Never>?
    private let tutorialStep: OnboardingPart2Step?

    @MainActor
    init(tutorialStep: OnboardingPart2Step? = nil) {
        _viewModel = StateObject(wrappedValue: HomeViewModel())
        self.tutorialStep = tutorialStep
    }

    @MainActor
    init(viewModel: HomeViewModel, tutorialStep: OnboardingPart2Step? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.tutorialStep = tutorialStep
    }

    var body: some View {
        let hasSelectedImage = viewModel.selectedImageData != nil

        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isTutorialMode {
                    tutorialTitlePlaceholder
                }

                Text("Love Balance")
                    .font(.title2.weight(.semibold))
                    .tutorialHidden(viewModel.isTutorialMode)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .frame(width: 116, height: 116)
                    .overlay {
                        Text("\(session.group?.loveBalance ?? 0)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .accessibilityIdentifier("home.balance")
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .tutorialTarget(.balanceValue)

                VStack(spacing: 12) {
                    Text("Tap Count: \(viewModel.tapCount)")
                        .accessibilityIdentifier("home.tapCount")
                    Text("Predicted Delta: \(viewModel.predictedDelta >= 0 ? "+" : "")\(viewModel.predictedDelta)")
                        .foregroundStyle(viewModel.predictedDelta >= 0 ? .green : .red)
                        .accessibilityIdentifier("home.predictedDelta")
                }
                .font(.headline)
                .tutorialHidden(viewModel.isTutorialMode)

                Button {
                    triggerTapFeedback(for: viewModel.type)
                    viewModel.registerTap()
                } label: {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .frame(width: 116, height: 116)
                        .overlay {
                            HomeTapButtonFeedbackLabel(
                                type: viewModel.type,
                                state: tapFeedbackState
                            )
                        }
                        .tutorialTarget(.tapButton)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(!isHeartInteractive)
                .accessibilityIdentifier("home.tapButton")

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .top
            )
            .padding()
        }
        .navigationTitle(viewModel.isTutorialMode ? "" : "Home")
        .scrollBounceBehavior(.always)
        .refreshable {
            guard !viewModel.isTutorialMode else { return }
            await session.refreshHome()
        }
        .safeAreaInset(edge: .top) {
            RefreshStatusView(state: session.refreshState(for: .home))
        }
        .safeAreaInset(edge: .bottom) {
            Picker("Type", selection: $viewModel.type) {
                Text("+").tag(EventType.deposit)
                Text("-").tag(EventType.withdraw)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .disabled(viewModel.isTutorialMode)
            .accessibilityIdentifier("home.typePicker")
            .tutorialHidden(viewModel.isTutorialMode)
        }
        .sheet(isPresented: $viewModel.showComposer) {
            NavigationStack {
                Form {
                    Section("Burst Summary") {
                        Text("Tap Count: \(viewModel.tapCount)")
                        Text("Delta: \(viewModel.predictedDelta)")
                    }

                    Section("Note") {
                        TextField("Optional note", text: $viewModel.note, axis: .vertical)
                            .lineLimit(3...6)
                            .disabled(!isNoteInteractive)
                            .accessibilityIdentifier("home.note")
                        Text("If empty, default note will use time + location.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !viewModel.isTutorialMode {
                        EventLocationEditorSection(
                            title: "Location",
                            draft: $composerLocation,
                            currentLocation: currentEditableLocation,
                            accessibilityPrefix: "home.location",
                            isDisabled: false
                        )
                    }

                    Section("Image") {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text(hasSelectedImage ? "Replace Image" : "Add Image")
                        }
                        .disabled(!isPhotoInteractive)

                        if hasSelectedImage {
                            Text("Image selected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Submit Event")
                .accessibilityIdentifier("home.composer")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            viewModel.resetBurst()
                        }
                        .disabled(viewModel.isTutorialMode)
                        .accessibilityIdentifier("home.cancel")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Submit") {
                            Task {
                                await viewModel.submit(
                                    using: session,
                                    location: composerLocation.eventLocation
                                )
                            }
                        }
                        .disabled(viewModel.tapCount == 0 || !isSubmitInteractive || (!viewModel.isTutorialMode && composerLocation.eventLocation == nil))
                        .accessibilityIdentifier("home.submit")
                        .tutorialTarget(.submit)
                    }
                }
                .alert(
                    "Error",
                    isPresented: Binding(
                        get: { session.globalErrorMessage != nil },
                        set: { newValue in
                            if !newValue {
                                session.globalErrorMessage = nil
                            }
                        }
                    ),
                    actions: {
                        Button("OK", role: .cancel) {
                            session.globalErrorMessage = nil
                        }
                    },
                    message: {
                        Text(session.globalErrorMessage ?? "Unknown error")
                    }
                )
            }
            .overlayPreferenceValue(TutorialTargetPreferenceKey.self) { anchors in
                if isComposerTutorialStep {
                    GeometryReader { proxy in
                        TutorialOverlayView(
                            step: tutorialStep ?? .submitDraft,
                            targetFrames: anchors.mapValues { proxy[$0] },
                            size: proxy.size
                        )
                        .allowsHitTesting(false)
                    }
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
                            viewModel.selectedImageData = nil
                            viewModel.selectedImageExtension = "jpg"
                            return
                        }
                        let utType = newValue.supportedContentTypes.first
                        let ext = utType?.preferredFilenameExtension?.lowercased() ?? "jpg"
                        viewModel.selectedImageData = data
                        viewModel.selectedImageExtension = ext
                    }
                }
            }
        }
        .task {
            guard !viewModel.isTutorialMode else { return }
            locationManager.requestAuthorizationIfNeeded()
        }
        .onChange(of: viewModel.showComposer) { _, isPresented in
            if isPresented {
                seedComposerLocationIfNeeded()
            } else {
                composerLocation = EditableEventLocation()
            }
        }
        .onDisappear {
            tapFeedbackTask?.cancel()
        }
    }

    private var tutorialTitlePlaceholder: some View {
        HStack {
            Text("Home")
                .font(.system(size: 40, weight: .bold))
                .tutorialHidden(viewModel.isTutorialMode)
            Spacer()
        }
    }

    private var isHeartInteractive: Bool {
        guard let tutorialStep else { return true }
        return tutorialStep == .focusHeart
    }

    private var isNoteInteractive: Bool {
        guard tutorialStep != nil else { return true }
        return false
    }

    private var isPhotoInteractive: Bool {
        guard tutorialStep != nil else { return true }
        return false
    }

    private var isSubmitInteractive: Bool {
        guard let tutorialStep else { return true }
        return tutorialStep == .submitDraft
    }

    private var isComposerTutorialStep: Bool {
        guard let tutorialStep else { return false }
        switch tutorialStep {
        case .submitDraft:
            return true
        default:
            return false
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

    private func seedComposerLocationIfNeeded() {
        guard composerLocation.isBlank, let currentEditableLocation else { return }
        composerLocation = currentEditableLocation
    }

    private func triggerTapFeedback(for type: EventType) {
        let style = HomeTapFeedbackStyle.forType(type)
        tapFeedbackTask?.cancel()
        tapFeedbackState = style.preImpactState

        withAnimation(style.impactAnimation) {
            tapFeedbackState = style.impactState
        }

        tapFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: style.impactDuration.nanoseconds)
            guard !Task.isCancelled else { return }

            withAnimation(style.settleAnimation) {
                tapFeedbackState = .rest
            }
        }
    }
}

private struct HomeTapButtonFeedbackLabel: View {
    let type: EventType
    let state: HomeTapFeedbackState

    private var tint: Color {
        type == .deposit ? .pink : .red
    }

    private var symbolName: String {
        type == .deposit ? "heart.fill" : "heart.slash.fill"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(state.plateOpacity))
                .frame(width: 92, height: 92)
                .scaleEffect(state.plateScale)

            Circle()
                .stroke(tint.opacity(state.pulseOpacity), lineWidth: 7)
                .frame(width: 86, height: 86)
                .scaleEffect(state.pulseScale)

            Image(systemName: symbolName)
                .font(.system(size: 70))
                .foregroundStyle(tint)
                .scaleEffect(state.symbolScale)
                .rotationEffect(.degrees(state.rotationDegrees))
                .offset(x: state.xOffset, y: state.yOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private extension View {
    @ViewBuilder
    func tutorialHidden(_ hidden: Bool) -> some View {
        if hidden {
            self
                .opacity(0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        } else {
            self
        }
    }
}

struct EditableEventLocation: Equatable {
    var addressText: String
    var latitudeText: String
    var longitudeText: String

    init(addressText: String = "", latitudeText: String = "", longitudeText: String = "") {
        self.addressText = addressText
        self.latitudeText = latitudeText
        self.longitudeText = longitudeText
    }

    init(addressText: String = "", latitude: Double, longitude: Double) {
        self.addressText = addressText
        self.latitudeText = Self.formatCoordinate(latitude)
        self.longitudeText = Self.formatCoordinate(longitude)
    }

    var eventLocation: EventLocation? {
        guard let latitude = Double(latitudeText.trimmedText),
              let longitude = Double(longitudeText.trimmedText),
              latitude.isFinite,
              longitude.isFinite,
              Self.validLatitudeRange.contains(latitude),
              Self.validLongitudeRange.contains(longitude) else {
            return nil
        }

        return EventLocation(
            lat: latitude,
            lng: longitude,
            addressText: addressText.trimmedText.nilIfEmpty
        )
    }

    var isBlank: Bool {
        addressText.trimmedText.isEmpty
            && latitudeText.trimmedText.isEmpty
            && longitudeText.trimmedText.isEmpty
    }

    var showsInvalidCoordinates: Bool {
        let hasCoordinateInput = !latitudeText.trimmedText.isEmpty || !longitudeText.trimmedText.isEmpty
        return hasCoordinateInput && eventLocation == nil
    }

    private static func formatCoordinate(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static let validLatitudeRange = -90.0...90.0
    private static let validLongitudeRange = -180.0...180.0
}

struct EventLocationEditorSection: View {
    let title: String
    @Binding var draft: EditableEventLocation
    let currentLocation: EditableEventLocation?
    let accessibilityPrefix: String
    let isDisabled: Bool

    var body: some View {
        Section(title) {
            TextField("Address or label", text: $draft.addressText)
                .disabled(isDisabled)
                .accessibilityIdentifier("\(accessibilityPrefix).address")

            TextField("Latitude", text: $draft.latitudeText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isDisabled)
                .accessibilityIdentifier("\(accessibilityPrefix).latitude")

            TextField("Longitude", text: $draft.longitudeText)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isDisabled)
                .accessibilityIdentifier("\(accessibilityPrefix).longitude")

            if let currentLocation {
                Button("Use Current Location") {
                    draft = currentLocation
                }
                .disabled(isDisabled)
                .accessibilityIdentifier("\(accessibilityPrefix).current")
            }

            if draft.showsInvalidCoordinates {
                Text("Enter latitude from -90 to 90 and longitude from -180 to 180.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct HomeTapFeedbackState {
    var symbolScale: CGFloat = 1
    var xOffset: CGFloat = 0
    var yOffset: CGFloat = 0
    var rotationDegrees: Double = 0
    var pulseScale: CGFloat = 0.82
    var pulseOpacity: Double = 0
    var plateScale: CGFloat = 0.92
    var plateOpacity: Double = 0

    static let rest = HomeTapFeedbackState()
}

// Keep the tap feel tunable in one place without touching Home event logic.
private struct HomeTapFeedbackStyle {
    let compression: CGFloat
    let scaleBoost: CGFloat
    let pressDepth: CGFloat
    let lift: CGFloat
    let horizontalKick: CGFloat
    let twistDegrees: Double
    let pulseScale: CGFloat
    let pulseOpacity: Double
    let plateOpacity: Double
    let impactDuration: TimeInterval
    let impactBounce: Double
    let settleDuration: TimeInterval

    var impactAnimation: Animation {
        .spring(duration: impactDuration, bounce: impactBounce)
    }

    var settleAnimation: Animation {
        .easeOut(duration: settleDuration)
    }

    var preImpactState: HomeTapFeedbackState {
        HomeTapFeedbackState(
            symbolScale: 1 - compression,
            xOffset: horizontalKick == 0 ? 0 : -horizontalKick * 0.55,
            yOffset: pressDepth,
            rotationDegrees: twistDegrees * -0.35,
            pulseScale: 0.84,
            pulseOpacity: pulseOpacity * 0.35,
            plateScale: 0.92,
            plateOpacity: plateOpacity * 0.6
        )
    }

    var impactState: HomeTapFeedbackState {
        HomeTapFeedbackState(
            symbolScale: 1 + scaleBoost,
            xOffset: horizontalKick,
            yOffset: -lift,
            rotationDegrees: twistDegrees,
            pulseScale: pulseScale,
            pulseOpacity: pulseOpacity,
            plateScale: 1.02,
            plateOpacity: plateOpacity
        )
    }

    static func forType(_ type: EventType) -> HomeTapFeedbackStyle {
        switch type {
        case .deposit:
            return HomeTapFeedbackStyle(
                compression: 0.08,
                scaleBoost: 0.18,
                pressDepth: 4,
                lift: 8,
                horizontalKick: 0,
                twistDegrees: -8,
                pulseScale: 1.26,
                pulseOpacity: 0.22,
                plateOpacity: 0.16,
                impactDuration: 0.18,
                impactBounce: 0.42,
                settleDuration: 0.14
            )
        case .withdraw:
            return HomeTapFeedbackStyle(
                compression: 0.10,
                scaleBoost: 0.08,
                pressDepth: 3,
                lift: 2,
                horizontalKick: 5,
                twistDegrees: 8,
                pulseScale: 1.12,
                pulseOpacity: 0.16,
                plateOpacity: 0.12,
                impactDuration: 0.16,
                impactBounce: 0.24,
                settleDuration: 0.12
            )
        }
    }
}

private extension String {
    var trimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let trimmed = trimmedText
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension TimeInterval {
    var nanoseconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
