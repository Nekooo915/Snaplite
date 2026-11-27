#!/usr/bin/env swift
// Render the app icon of a built .app bundle to PNGs in light and dark appearance.
//
// Usage:
//   swift scripts/render-app-icon.swift dist/Snaplite.app <out-dir> [pixels=1024]
//
// Uses NSWorkspace (IconServices), i.e. exactly what Finder / Dock resolve from
// Assets.car (CFBundleIconName) or AppIcon.icns. Each appearance is rendered
// with NSApp.appearance + performAsCurrentDrawingAppearance so layered
// (Icon Composer) icons resolve their light / dark specializations.

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: render-app-icon.swift <App.app> <out-dir> [pixels]\n".data(using: .utf8)!)
    exit(2)
}
let appPath = args[1]
let outDir = URL(fileURLWithPath: args[2])
let pixels = args.count > 3 ? Int(args[3]) ?? 1024 : 1024
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let app = NSApplication.shared
_ = app

@MainActor
func render(_ name: String, appearance: NSAppearance) throws {
    NSApp.appearance = appearance
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
    let url = outDir.appendingPathComponent("compiled-\(name)-\(pixels).png")
    try png.write(to: url)
    print("wrote \(url.path)")
}

try MainActor.assumeIsolated {
    try render("light", appearance: NSAppearance(named: .aqua)!)
    try render("dark", appearance: NSAppearance(named: .darkAqua)!)
}
