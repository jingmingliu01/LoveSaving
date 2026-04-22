import FirebaseStorage
import SwiftUI
import UIKit

struct EventMediaInlinePreview: View {
    let media: EventMedia
    let additionalImageCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                EventMediaImageContainer(media: media) { image in
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 220)
                .padding(12)
                .background(Color.secondary.opacity(0.08))

                if additionalImageCount > 0 {
                    Text("+\(additionalImageCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15))
            }
        }
        .buttonStyle(.plain)
    }
}

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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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

private struct EventMediaImageContainer<Content: View>: View {
    let media: EventMedia
    let content: (UIImage) -> Content

    @State private var phase: EventMediaImagePhase = .loading

    init(media: EventMedia, @ViewBuilder content: @escaping (UIImage) -> Content) {
        self.media = media
        self.content = content
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.regular)
            case .loaded(let image):
                content(image)
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
        if let cached = EventMediaImageLoader.imageCache.object(forKey: cacheKey) {
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

            EventMediaImageLoader.imageCache.setObject(image, forKey: cacheKey)
            phase = .loaded(image)
        } catch {
            phase = .failed
        }
    }

    private func imageData(for media: EventMedia) async throws -> Data {
        if let inlineData = EventMediaImageLoader.decodeInlineDataURL(media.storagePath) {
            return inlineData
        }

        let reference = Storage.storage().reference(withPath: media.storagePath)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            reference.getData(maxSize: EventMediaImageLoader.maxDownloadBytes) { data, error in
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

}

private enum EventMediaImageLoader {
    static let imageCache = NSCache<NSString, UIImage>()
    static let maxDownloadBytes: Int64 = 10 * 1024 * 1024

    static func decodeInlineDataURL(_ storagePath: String) -> Data? {
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

private enum EventMediaImagePhase {
    case loading
    case loaded(UIImage)
    case failed
}

private struct EventMediaPreviewImage: View {
    let media: EventMedia

    var body: some View {
        EventMediaImageContainer(media: media) { image in
            ZoomableEventMediaImage(image: image)
        }
    }
}

private struct ZoomableEventMediaImage: View {
    let image: UIImage

    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1

    private let minimumZoomScale: CGFloat = 1
    private let maximumZoomScale: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let fittedSize = image.size.aspectFit(in: proxy.size)
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: fittedSize.width * zoomScale,
                        height: fittedSize.height * zoomScale
                    )
                    .frame(
                        width: max(proxy.size.width, fittedSize.width * zoomScale),
                        height: max(proxy.size.height, fittedSize.height * zoomScale)
                    )
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoomScale = clampedZoomScale(committedZoomScale * value)
                    }
                    .onEnded { value in
                        let updatedZoomScale = clampedZoomScale(committedZoomScale * value)
                        zoomScale = updatedZoomScale
                        committedZoomScale = updatedZoomScale
                    }
            )
            .onTapGesture(count: 2) {
                let updatedZoomScale = zoomScale > minimumZoomScale ? minimumZoomScale : 2
                zoomScale = updatedZoomScale
                committedZoomScale = updatedZoomScale
            }
        }
    }

    private func clampedZoomScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumZoomScale), maximumZoomScale)
    }
}

private extension CGSize {
    func aspectFit(in container: CGSize) -> CGSize {
        guard width > 0, height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }

        let widthRatio = container.width / width
        let heightRatio = container.height / height
        let scale = min(widthRatio, heightRatio)

        return CGSize(width: width * scale, height: height * scale)
    }
}
