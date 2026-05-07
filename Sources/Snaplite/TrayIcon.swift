import AppKit

/// Procedurally rendered menubar glyph: a dashed selection rectangle with
/// a solid filled square in the top-left corner. Pixel-for-pixel port of
/// the Rust build's `make_tray_icon`. Marked as a template image so the
/// system recolours it for light/dark menubars.
enum TrayIcon {
    /// 44×44 source bitmap, declared at logical 18×18 pt — the standard
    /// menubar icon size — so AppKit downscales cleanly on @1x displays
    /// while keeping crisp lines on Retina.
    static func makeImage() -> NSImage {
        let SIZE = 44
        let PAD = 4
        let STROKE = 3
        let DASH_ON = 5
        let DASH_OFF = 3
        let CORNER = 13
        let cycle = DASH_ON + DASH_OFF

        var buf = [UInt8](repeating: 0, count: SIZE * SIZE * 4)

        func put(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < SIZE, y < SIZE else { return }
            let i = (y * SIZE + x) * 4
            buf[i] = 0
            buf[i + 1] = 0
            buf[i + 2] = 0
            buf[i + 3] = 255
        }

        let x0 = PAD
        let y0 = PAD
        let x1 = SIZE - PAD - 1
        let y1 = SIZE - PAD - 1

        // Dashed horizontal edges (top + bottom), STROKE px thick.
        for x in x0...x1 {
            if (x - x0) % cycle >= DASH_ON { continue }
            for t in 0..<STROKE {
                put(x, y0 + t)
                put(x, y1 - t)
            }
        }
        // Dashed vertical edges (left + right), STROKE px thick.
        for y in y0...y1 {
            if (y - y0) % cycle >= DASH_ON { continue }
            for t in 0..<STROKE {
                put(x0 + t, y)
                put(x1 - t, y)
            }
        }
        // Solid filled corner at the top-left.
        for y in y0..<(y0 + CORNER) {
            for x in x0..<(x0 + CORNER) {
                put(x, y)
            }
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: SIZE,
            pixelsHigh: SIZE,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: SIZE * 4,
            bitsPerPixel: 32
        ), let pixelData = bitmap.bitmapData else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        buf.withUnsafeBufferPointer { src in
            memcpy(pixelData, src.baseAddress, src.count)
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
