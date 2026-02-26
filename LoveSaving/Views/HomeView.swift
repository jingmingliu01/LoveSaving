import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var locationManager: LocationManager

    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        let hasSelectedImage = viewModel.selectedImageData != nil

        VStack(spacing: 20) {
            Text("Love Balance")
                .font(.title2.weight(.semibold))

            Text("\(session.group?.loveBalance ?? 0)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .accessibilityIdentifier("home.balance")

            VStack(spacing: 12) {
                Text("Tap Count: \(viewModel.tapCount)")
                    .accessibilityIdentifier("home.tapCount")
                Text("Predicted Delta: \(viewModel.predictedDelta >= 0 ? "+" : "")\(viewModel.predictedDelta)")
                    .foregroundStyle(viewModel.predictedDelta >= 0 ? .green : .red)
                    .accessibilityIdentifier("home.predictedDelta")
            }
            .font(.headline)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                    viewModel.registerTap()
                }
            } label: {
                Image(systemName: viewModel.type == .deposit ? "heart.fill" : "heart.slash.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(viewModel.type == .deposit ? .pink : .red)
                    .scaleEffect(viewModel.tapCount > 0 ? 1.06 : 1.0)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.tapButton")

            Spacer()
        }
        .padding()
        .navigationTitle("Home")
        .safeAreaInset(edge: .bottom) {
            Picker("Type", selection: $viewModel.type) {
                Text("+").tag(EventType.deposit)
                Text("-").tag(EventType.withdraw)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("home.typePicker")
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
                            .accessibilityIdentifier("home.note")
                        Text("If empty, default note will use time + location.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Image") {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text(hasSelectedImage ? "Replace Image" : "Add Image")
                        }

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
                        .disabled(viewModel.tapCount == 0)
                        .accessibilityIdentifier("home.submit")
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
            locationManager.requestAuthorizationIfNeeded()
        }
    }
}
