import AppKit
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SnapliteCore

@Suite("Pasteboard & Capturer")
struct PasteboardAndCapturerTests {
    private func makeTestPNGFile() throws -> (URL, Data) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0x33, 0x66, 0xCC, 0xFF]
        let ctx = try #require(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(ctx.makeImage())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplite-pb-\(UUID().uuidString).png")
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        let data = try Data(contentsOf: url)
        return (url, data)
    }

    @Test("Writes single NSPasteboardItem with eager PNG and lazy TIFF surviving file deletion")
    @MainActor
    func pasteboardSingleItemAndLazyTIFF() throws {
        let (pngURL, originalPNG) = try makeTestPNGFile()
        let pb = NSPasteboard.withUniqueName()
        defer {
            pb.clearContents()
            pb.releaseGlobally()
            try? FileManager.default.removeItem(at: pngURL)
        }

        let ok = Pasteboard.writePNG(contentsOf: pngURL, to: pb)
        #expect(ok)

        // Delete the source file immediately to prove lazy TIFF still works via pboard PNG bytes.
        try FileManager.default.removeItem(at: pngURL)

        let items = try #require(pb.pasteboardItems)
        #expect(items.count == 1)
        #expect(items[0].types.contains(.png))
        #expect(items[0].types.contains(.tiff))

        let readPNG = try #require(pb.data(forType: .png))
        #expect(readPNG == originalPNG)

        let readTIFF = try #require(pb.data(forType: .tiff))
        #expect(readTIFF.count > 8)
        // Standard TIFF magic bytes: little-endian ("II*\0") or big-endian ("MM\0*").
        let header = Array(readTIFF.prefix(4))
        let isLittleEndianTIFF = header == [0x49, 0x49, 0x2A, 0x00]
        let isBigEndianTIFF = header == [0x4D, 0x4D, 0x00, 0x2A]
        #expect(isLittleEndianTIFF || isBigEndianTIFF)
    }

    @Test("Capturer gates on Screen Recording permission and reports invalid save folder")
    @MainActor
    func capturerPermissionAndErrorGates() throws {
        var permissionTriggered = false
        let deniedCapturer = Capturer(permissionCheck: { false })
        deniedCapturer.onPermissionRequired = { permissionTriggered = true }
        deniedCapturer.capture(mode: .copy, saveDir: "/tmp")
        #expect(permissionTriggered)
        #expect(!deniedCapturer.isCapturing)

        let blockerFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplite-blocker-\(UUID().uuidString)")
        try Data("not-a-dir".utf8).write(to: blockerFile)
        defer { try? FileManager.default.removeItem(at: blockerFile) }

        var errorMessage: String?
        let errorCapturer = Capturer(
            permissionCheck: { true },
            stringsProvider: { .en }
        )
        errorCapturer.onError = { errorMessage = $0 }
        errorCapturer.capture(mode: .save, saveDir: blockerFile.path)
        #expect(errorMessage == Strings.en.errorSaveFolderUnavailable)
        #expect(!errorCapturer.isCapturing)
    }
}
