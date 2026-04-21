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
            .background(Color(.systemBackground))
            .navigationTitle(event.media.count == 1 ? "Image" : "Images")
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
        GeometryReader { proxy in
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                EventMediaPreviewImage(
                    media: media,
                    maxWidth: min(proxy.size.width - 40, 420),
                    maxHeight: min(proxy.size.height * 0.62, 460)
                )

                if totalCount > 1 {
                    Text("\(index + 1) / \(totalCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }

                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .padding(.vertical, 24)
        }
    }
}

struct EventMediaThumbnailStrip: View {
    let media: [EventMedia]
    let onSelect: () -> Void

    private let maxVisibleCount = 4

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(visibleMedia.enumerated()), id: \.offset) { index, item in
                    Button {
                        onSelect()
                    } label: {
                        EventMediaThumbnail(
                            media: item,
                            remainingCount: remainingCount(for: index)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("journey.imagePreview.thumbnail")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("journey.imagePreview.open")
    }

    private var visibleMedia: [EventMedia] {
        Array(media.prefix(maxVisibleCount))
    }

    private func remainingCount(for index: Int) -> Int? {
        guard index == visibleMedia.count - 1, media.count > visibleMedia.count else {
            return nil
        }
        return media.count - visibleMedia.count
    }
}

private struct EventMediaThumbnail: View {
    let media: EventMedia
    let remainingCount: Int?

    var body: some View {
        EventMediaImageLoader(media: media) { phase in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemBackground))

                switch phase {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                case .loaded(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipped()
                case .failed:
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let remainingCount {
                    Color.black.opacity(0.45)
                    Text("+\(remainingCount)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EventMediaPreviewImage: View {
    let media: EventMedia
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        EventMediaImageLoader(media: media) { phase in
            Group {
                switch phase {
                case .loading:
                    ProgressView("Loading image...")
                        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                case .loaded(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                case .failed:
                    ContentUnavailableView(
                        "Unable to Load Image",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("This attachment could not be previewed right now.")
                    )
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                }
            }
            .frame(width: maxWidth, height: maxHeight)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private enum EventMediaImagePhase {
    case loading
    case loaded(UIImage)
    case failed
}

private struct EventMediaImageLoader<Content: View>: View {
    let media: EventMedia
    @ViewBuilder let content: (EventMediaImagePhase) -> Content

    @State private var phase: EventMediaImagePhase = .loading

    var body: some View {
        content(phase)
            .task(id: media.storagePath) {
                await loadImage()
            }
    }

    @MainActor
    private func loadImage() async {
        let cacheKey = media.storagePath as NSString
        if let cached = EventMediaImageStore.imageCache.object(forKey: cacheKey) {
            phase = .loaded(cached)
            return
        }

        phase = .loading

        do {
            let data = try await EventMediaImageStore.imageData(for: media)
            guard let image = UIImage(data: data) else {
                phase = .failed
                return
            }

            EventMediaImageStore.imageCache.setObject(image, forKey: cacheKey)
            phase = .loaded(image)
        } catch {
            phase = .failed
        }
    }
}

private enum EventMediaImageStore {
    static let imageCache = NSCache<NSString, UIImage>()
    static let maxDownloadBytes: Int64 = 10 * 1024 * 1024

    static func imageData(for media: EventMedia) async throws -> Data {
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
