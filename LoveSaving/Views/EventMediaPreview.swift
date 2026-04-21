import FirebaseStorage
import SwiftUI
import UIKit

struct EventMediaPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let event: LoveEvent

    var body: some View {
        NavigationStack {
            TabView {
                ForEach(Array(event.media.enumerated()), id: \.offset) { index, media in
                    EventMediaPreviewPage(
                        media: media,
                        index: index,
                        totalCount: event.media.count
                    )
                }
            }
            .tabViewStyle(.page(indexDisplayMode: event.media.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Image Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct EventMediaPreviewPage: View {
    let media: EventMedia
    let index: Int
    let totalCount: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()

            EventMediaPreviewImage(media: media)
                .padding()

            if totalCount > 1 {
                Text("\(index + 1) / \(totalCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding()
            }
        }
    }
}

private struct EventMediaPreviewImage: View {
    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    private static let imageCache = NSCache<NSString, UIImage>()
    private static let maxDownloadBytes: Int64 = 10 * 1024 * 1024

    let media: EventMedia

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading image...")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .loaded(let image):
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                minWidth: proxy.size.width,
                                minHeight: proxy.size.height
                            )
                    }
                    .scrollIndicators(.hidden)
                }
            case .failed:
                ContentUnavailableView(
                    "Unable to Load Image",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("This attachment could not be previewed right now.")
                )
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: media.storagePath) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        let cacheKey = media.storagePath as NSString
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            phase = .loaded(cached)
            return
        }

        phase = .loading

        do {
            let data = try await imageData(for: media)
            guard let image = UIImage(data: data) else {
                phase = .failed
                return
            }

            Self.imageCache.setObject(image, forKey: cacheKey)
            phase = .loaded(image)
        } catch {
            phase = .failed
        }
    }

    private func imageData(for media: EventMedia) async throws -> Data {
        if let inlineData = Self.decodeInlineDataURL(media.storagePath) {
            return inlineData
        }

        let reference = Storage.storage().reference(withPath: media.storagePath)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            reference.getData(maxSize: Self.maxDownloadBytes) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: AppError.eventNotFound)
                }
            }
        }
    }

    private static func decodeInlineDataURL(_ storagePath: String) -> Data? {
        guard storagePath.hasPrefix("data:"),
              let separatorIndex = storagePath.firstIndex(of: ",") else {
            return nil
        }

        let metadata = storagePath[..<separatorIndex]
        let payload = storagePath[storagePath.index(after: separatorIndex)...]

        if metadata.contains(";base64") {
            return Data(base64Encoded: String(payload))
        }

        return String(payload).removingPercentEncoding?.data(using: .utf8)
    }
}
