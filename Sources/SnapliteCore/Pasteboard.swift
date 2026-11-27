import AppKit
import ImageIO
import UniformTypeIdentifiers
import os

/// Zero-eager-decode pasteboard writer.
///
/// Writes a single `NSPasteboardItem` containing the PNG bytes directly plus a lazy
/// `NSPasteboardItemDataProvider` for `.tiff`, so TIFF transcoding only happens if
/// a paste target explicitly requests `.tiff`.
public enum Pasteboard {
    /// Writes a PNG file onto `pasteboard` as a single item with eager `.png` data
    /// and lazy `.tiff` transcoding. Returns `true` on success.
    @MainActor
    @discardableResult
    public static func writePNG(
        contentsOf url: URL,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let pngData = try? Data(contentsOf: url, options: .mappedIfSafe),
              !pngData.isEmpty else {
            return false
        }

        let item = NSPasteboardItem()
        guard item.setData(pngData, forType: .png) else {
            return false
        }

        let provider = LazyTIFFDataProvider(sourceURL: url)
        guard item.setDataProvider(provider, forTypes: [.tiff]) else {
            return false
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            return false
        }

        LazyTIFFDataProvider.retain(provider)
        return true
    }

    /// Transcodes PNG data into TIFF data via `CGImageSource` / `CGImageDestination`.
    internal static func transcodePNGToTIFF(_ pngData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    /// Test observability counter for active lazy TIFF providers.
    internal static var activeProviderCount: Int {
        LazyTIFFDataProvider.activeCount
    }
}

private final class LazyTIFFDataProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private static let retainedLock = OSAllocatedUnfairLock<[ObjectIdentifier: LazyTIFFDataProvider]>(
        initialState: [:]
    )

    static func retain(_ provider: LazyTIFFDataProvider) {
        retainedLock.withLock { $0[ObjectIdentifier(provider)] = provider }
    }

    static func release(_ provider: LazyTIFFDataProvider) {
        _ = retainedLock.withLock { $0.removeValue(forKey: ObjectIdentifier(provider)) }
    }

    static var activeCount: Int {
        retainedLock.withLock { $0.count }
    }

    private let sourceURL: URL

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        super.init()
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .tiff else { return }
        // Prefer PNG bytes already held by the pasteboard server so moving or deleting
        // the saved file on disk never breaks lazy TIFF pasting, and Snaplite keeps
        // zero image bytes resident in its own heap.
        let pngData = pasteboard?.data(forType: .png)
            ?? (try? Data(contentsOf: sourceURL, options: .mappedIfSafe))
        guard let pngData, let tiffData = Pasteboard.transcodePNGToTIFF(pngData) else {
            return
        }
        item.setData(tiffData, forType: .tiff)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        Self.release(self)
    }
}
