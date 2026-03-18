import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var locationManager: LocationManager

    @StateObject private var viewModel: HomeViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                        viewModel.registerTap()
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .frame(width: 116, height: 116)
                        .overlay {
                            Image(systemName: viewModel.type == .deposit ? "heart.fill" : "heart.slash.fill")
                                .font(.system(size: 70))
                                .foregroundStyle(viewModel.type == .deposit ? .pink : .red)
                                .scaleEffect(viewModel.tapCount > 0 ? 1.06 : 1.0)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                                    coordinate: locationManager.coordinate.map { ($0.latitude, $0.longitude) },
                                    addressText: locationManager.addressText
                                )
                            }
                        }
                        .disabled(viewModel.tapCount == 0 || !isSubmitInteractive)
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
