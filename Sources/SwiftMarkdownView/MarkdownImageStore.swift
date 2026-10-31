import Foundation
import ImageIO

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads the bytes of an embedded image from its source as written.
typealias MarkdownImageLoader = @Sendable (String) async -> Data?

/// An image loader and the identity that scopes the sources it loads: the
/// same path can mean different files to loaders with different IDs.
/// Loaders with the same ID are treated as interchangeable.
struct MarkdownImageLoading: Equatable, @unchecked Sendable {
    /// Hashable and Sendable, from `markdownImageLoader(id:_:)`.
    let id: AnyHashable
    let load: MarkdownImageLoader

    init(id: some Hashable & Sendable, load: @escaping MarkdownImageLoader) {
        self.id = AnyHashable(id)
        self.load = load
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    private struct DefaultID: Hashable, Sendable {}

    /// Fetches http, https and data URLs; any other source shows its alt text.
    static let `default` = MarkdownImageLoading(id: DefaultID()) { source in
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "data"].contains(scheme),
              let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            return nil
        }
        return data
    }
}

/// Identifies an embedded image: its source, as understood by one loader.
struct MarkdownImageKey: Hashable, @unchecked Sendable {
    let loaderID: AnyHashable
    let source: String
}

/// A decoded image, downsampled so its longest side is at most
/// `MarkdownImageStore.maxPixelSize`.
final class MarkdownImageAsset: @unchecked Sendable {
    let cgImage: CGImage
    /// The image's size in pixels before downsampling, upright.
    let pixelSize: CGSize

    init(cgImage: CGImage, pixelSize: CGSize) {
        self.cgImage = cgImage
        self.pixelSize = pixelSize
    }

    var cost: Int { cgImage.bytesPerRow * cgImage.height }

    @MainActor
    var platformImage: PlatformImage {
        #if os(macOS)
        NSImage(cgImage: cgImage, size: .zero)
        #else
        UIImage(cgImage: cgImage)
        #endif
    }

    /// Decodes PNG, JPEG, GIF (first frame), HEIC, WebP and the other formats
    /// ImageIO reads, applying EXIF orientation.
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) -> MarkdownImageAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation >= 5 { swap(&width, &height) }

        let longestSide = Int(max(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide > 0 ? min(longestSide, maxPixelSize) : maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        if width <= 0 || height <= 0 {
            width = Double(image.width)
            height = Double(image.height)
        }
        return MarkdownImageAsset(cgImage: image, pixelSize: CGSize(width: width, height: height))
    }
}

/// Loads, decodes and caches embedded images by loader and source, shared by
/// every Markdown view so re-renders and views scrolled back into place show
/// images without reloading them.
///
/// Decoded images live in an `NSCache`; their sizes and failures are kept
/// after eviction, so a reloading image keeps its place in the layout.
@MainActor
final class MarkdownImageStore {
    /// What an image block is laid out as.
    enum LayoutState: Equatable {
        case pending
        case loaded(pixelSize: CGSize)
        case failed
    }

    static let shared = MarkdownImageStore()

    /// Longest side of a decoded image; larger images are downsampled.
    nonisolated static let maxPixelSize = 2560
    /// A failed image loads again when a view shows it after this long.
    private let failureRetryInterval: Duration = .seconds(30)

    private struct Client {
        weak var owner: AnyObject?
        let completion: @MainActor () -> Void
    }

    private final class Load {
        var task: Task<Void, Never>?
        var clients: [ObjectIdentifier: Client] = [:]
    }

    /// Wraps a key for `NSCache`, which needs object keys.
    private final class CacheKey: NSObject {
        let key: MarkdownImageKey

        init(_ key: MarkdownImageKey) {
            self.key = key
        }

        override var hash: Int { key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? CacheKey)?.key == key
        }
    }

    private let assets = NSCache<CacheKey, MarkdownImageAsset>()
    private var pixelSizes: [MarkdownImageKey: CGSize] = [:]
    private var failures: [MarkdownImageKey: ContinuousClock.Instant] = [:]
    private var loads: [MarkdownImageKey: Load] = [:]

    private init() {
        assets.totalCostLimit = 192 * 1024 * 1024
    }

    func asset(for key: MarkdownImageKey) -> MarkdownImageAsset? {
        assets.object(forKey: CacheKey(key))
    }

    func layoutState(for key: MarkdownImageKey) -> LayoutState {
        if let pixelSize = pixelSizes[key] { return .loaded(pixelSize: pixelSize) }
        if failures[key] != nil { return .failed }
        return .pending
    }

    func hasFailed(_ key: MarkdownImageKey) -> Bool {
        failures[key] != nil
    }

    /// Whether a view showing the image should load it.
    func needsLoad(_ key: MarkdownImageKey) -> Bool {
        guard asset(for: key) == nil else { return false }
        guard let failedAt = failures[key] else { return true }
        return ContinuousClock.now - failedAt >= failureRetryInterval
    }

    /// Loads an image for `owner`, sharing one load between every owner that
    /// asks for the same key. `completion` runs once the image has loaded or
    /// failed, unless the owner cancels or is deallocated first.
    func load(
        _ key: MarkdownImageKey,
        using loader: @escaping MarkdownImageLoader,
        for owner: AnyObject,
        completion: @escaping @MainActor () -> Void
    ) {
        let load: Load
        if let existing = loads[key] {
            load = existing
        } else {
            load = Load()
            loads[key] = load
            let source = key.source
            load.task = Task { [weak self, load] in
                let asset = await Self.fetch(source, using: loader)
                self?.finish(key, with: asset, load: load)
            }
        }
        load.clients[ObjectIdentifier(owner)] = Client(owner: owner, completion: completion)
    }

    /// Stops loading images for `owner`, except `keys`. Loads no other owner
    /// is waiting for are cancelled.
    func cancelLoads(for owner: AnyObject, keeping keys: Set<MarkdownImageKey> = []) {
        let id = ObjectIdentifier(owner)
        for (key, load) in loads where load.clients[id] != nil && !keys.contains(key) {
            load.clients[id] = nil
            load.clients = load.clients.filter { $0.value.owner != nil }
            if load.clients.isEmpty {
                load.task?.cancel()
                loads[key] = nil
            }
        }
    }

    private func finish(_ key: MarkdownImageKey, with asset: MarkdownImageAsset?, load: Load) {
        // A cancelled load has already been replaced or removed.
        guard loads[key] === load else { return }
        loads[key] = nil

        if let asset {
            assets.setObject(asset, forKey: CacheKey(key), cost: asset.cost)
            pixelSizes[key] = asset.pixelSize
            failures[key] = nil
        } else {
            pixelSizes[key] = nil
            failures[key] = .now
        }

        for client in load.clients.values where client.owner != nil {
            client.completion()
        }
    }

    @concurrent
    private nonisolated static func fetch(_ source: String, using loader: MarkdownImageLoader) async -> MarkdownImageAsset? {
        guard let data = await loader(source), !Task.isCancelled else { return nil }
        return MarkdownImageAsset.decode(data, maxPixelSize: maxPixelSize)
    }
}
