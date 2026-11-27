#!/usr/bin/env swift
// Render the app icon of a built .app bundle to a PNG in one appearance.
//
// Usage:
//   swift scripts/render-app-icon.swift <App.app> <out-dir> [pixels=1024] [light|dark]
//
// Uses NSWorkspace (IconServices), i.e. what Finder / Dock resolve from
// Assets.car (CFBundleIconName) or AppIcon.icns. Layered Icon Composer icons
// follow the *process* appearance, so scripts/render-icon.sh runs this once per
// appearance and forces dark with the `-AppleInterfaceStyle Dark` argument
// domain (no system setting is changed). NSApp.appearance and
// performAsCurrentDrawingAppearance are set as well for good measure.

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: render-app-icon.swift <App.app> <out-dir> [pixels] [light|dark]\n".data(using: .utf8)!)
    exit(2)
}
// NSWorkspace needs an absolute path; a relative one yields the generic document icon.
let appPath = URL(fileURLWithPath: args[1]).standardizedFileURL.path
guard FileManager.default.fileExists(atPath: appPath) else {
    FileHandle.standardError.write("no such bundle: \(appPath)\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
let pixels = args.count > 3 ? Int(args[3]) ?? 1024 : 1024
let mode = args.count > 4 && args[4] == "dark" ? "dark" : "light"
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

@MainActor
func render() throws {
    let appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)!
    NSApplication.shared.appearance = appearance
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw NSError(domain: "render", code: 1) }
    let points = CGFloat(pixels) / 2
    rep.size = NSSize(width: points, height: points)   // render as @2x

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    appearance.performAsCurrentDrawingAppearance {
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        icon.size = NSSize(width: points, height: points)
        icon.draw(in: NSRect(x: 0, y: 0, width: points, height: points),
                  from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render", code: 2)
    }
    let url = outDir.appendingPathComponent("compiled-\(mode)-\(pixels).png")
    try png.write(to: url)
    let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
    print("wrote \(url.path) (AppleInterfaceStyle=\(style), effective=\(NSApplication.shared.effectiveAppearance.name.rawValue))")
}

try MainActor.assumeIsolated { try render() }
