#!/usr/bin/env swift
// Reproducible generator for Snaplite's app icon ("Drag Corners", black & white).
//
// Usage (from anywhere):
//   swift scripts/make-icon.swift [--preview-dir <dir>]
//
// Writes:
//   assets/AppIcon.iconset/*.png      10 PNGs (16 … 512@2x), macOS 824/1024 grid + shadow (LIGHT palette)
//   assets/AppIcon.icns               via `iconutil -c icns`
//   assets/AppIcon.icon/Assets/*.svg  full-bleed Icon Composer layers (pane, corners)
//   <preview-dir>/AppIcon-{light,dark}-preview-1024.png   (only with --preview-dir; review aid, not an asset)
//
// Appearances (mirrored by assets/AppIcon.icon/icon.json):
//   light  white squircle (#FFFFFF → #ECECEF) + black glyph (#1C1C1E → #000000), pane black ~11%
//   dark   black squircle (#2C2C2E → #0A0A0A) + white glyph (#FFFFFF → #E8E8ED), pane white ~18%
// The static iconset/icns (macOS 14–25, or builds without actool) uses the LIGHT palette.
//
// Only CoreGraphics / ImageIO / Foundation are used — no third-party tools.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Paths

let repoURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetsURL = repoURL.appendingPathComponent("assets")
let iconsetURL = assetsURL.appendingPathComponent("AppIcon.iconset")
let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")
let layerDirURL = assetsURL.appendingPathComponent("AppIcon.icon/Assets")

var previewDirURL: URL?
do {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--preview-dir"), i + 1 < args.count {
        previewDirURL = URL(fileURLWithPath: args[i + 1])
    }
}

// MARK: - Helpers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, a])!
}

func white(_ a: CGFloat) -> CGColor { rgb(255, 255, 255, a) }
func black(_ a: CGFloat) -> CGColor { rgb(0, 0, 0, a) }

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

// MARK: - Palettes

/// One appearance of the icon. `ink` is the glyph family colour (pane tint, rims).
struct Palette {
    var name: String
    var backgroundTop: CGColor
    var backgroundBottom: CGColor
    var bracketTop: CGColor
    var bracketBottom: CGColor
    var ink: (CGFloat) -> CGColor          // pane tint at a given alpha
    var paneAlpha: CGFloat
    var paneRim: (top: CGColor, bottom: CGColor)
    var sheen: (CGFloat) -> CGColor        // top-left radial sheen colour
    var sheenScale: CGFloat                // multiplier on Optics.sheen
    var bracketShadowAlpha: CGFloat
    var outerShadowAlpha: CGFloat
    /// Inner rim on the squircle (half inside the clip).
    var bodyRim: [CGColor]
    /// Hairline outer border straddling the squircle edge (keeps a white tile visible on white).
    var bodyBorder: CGColor?

    static let light = Palette(
        name: "light",
        backgroundTop: rgb(0xFF, 0xFF, 0xFF),
        backgroundBottom: rgb(0xEC, 0xEC, 0xEF),
        bracketTop: rgb(0x1C, 0x1C, 0x1E),
        bracketBottom: rgb(0x00, 0x00, 0x00),
        ink: { black($0) },
        paneAlpha: 0.11,
        paneRim: (black(0.16), black(0.07)),
        sheen: { white($0) },
        sheenScale: 1.0,
        bracketShadowAlpha: 0.28,
        outerShadowAlpha: 0.26,
        bodyRim: [white(0.9), white(0.5), white(0.2)],
        bodyBorder: black(0.14)
    )

    static let dark = Palette(
        name: "dark",
        backgroundTop: rgb(0x2C, 0x2C, 0x2E),
        backgroundBottom: rgb(0x0A, 0x0A, 0x0A),
        bracketTop: rgb(0xFF, 0xFF, 0xFF),
        bracketBottom: rgb(0xE8, 0xE8, 0xED),
        ink: { white($0) },
        paneAlpha: 0.18,
        paneRim: (white(0.22), white(0.06)),
        sheen: { white($0) },
        sheenScale: 1.0,
        bracketShadowAlpha: 0.55,
        outerShadowAlpha: 0.32,
        bodyRim: [white(0.18), white(0.07), white(0.03)],
        bodyBorder: nil
    )
}

// MARK: - Design (1024 × 1024 full-bleed design space, y-down like SVG)

enum Design {
    static let canvas: CGFloat = 1024

    // Frosted pane (middle layer).
    static let paneRect = CGRect(x: 352, y: 352, width: 320, height: 320)
    static let paneRadius: CGFloat = 30

    // Corner brackets (top layer).
    static let bracketWidth: CGFloat = 96

    static let topLeftBracketSVG = "M258 490 V318 Q258 258 318 258 H490"
    static let bottomRightBracketSVG = "M766 534 V706 Q766 766 706 766 H534"

    static func bracketsPath() -> CGPath {
        let path = CGMutablePath()
        // Top-left: M258 490 V318 Q258 258 318 258 H490
        path.move(to: CGPoint(x: 258, y: 490))
        path.addLine(to: CGPoint(x: 258, y: 318))
        path.addQuadCurve(to: CGPoint(x: 318, y: 258), control: CGPoint(x: 258, y: 258))
        path.addLine(to: CGPoint(x: 490, y: 258))
        // Bottom-right: M766 534 V706 Q766 766 706 766 H534
        path.move(to: CGPoint(x: 766, y: 534))
        path.addLine(to: CGPoint(x: 766, y: 706))
        path.addQuadCurve(to: CGPoint(x: 706, y: 766), control: CGPoint(x: 766, y: 766))
        path.addLine(to: CGPoint(x: 534, y: 766))
        return path
    }

    // Legacy macOS grid: 824 × 824 continuous-corner body centered on 1024.
    static let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let bodyRadius: CGFloat = 185.4
}

/// Per-size optical adjustments for the static iconset.
struct Optics {
    var bracketScale: CGFloat   // multiplier on bracket stroke width
    var paneScale: CGFloat      // multiplier on palette pane alpha; 0 drops the pane entirely
    var paneRim: Bool           // hairline glass rim on the pane
    var bodyRim: Bool           // inner rim on the squircle
    var sheen: CGFloat          // peak opacity of the top-left radial sheen

    static func forPixelSize(_ px: Int) -> Optics {
        switch px {
        case ...16: return Optics(bracketScale: 1.28, paneScale: 0, paneRim: false, bodyRim: false, sheen: 0.12)
        case ...32: return Optics(bracketScale: 1.16, paneScale: 0.78, paneRim: false, bodyRim: true, sheen: 0.16)
        case ...64: return Optics(bracketScale: 1.06, paneScale: 0.94, paneRim: true, bodyRim: true, sheen: 0.20)
        default: return Optics(bracketScale: 1.00, paneScale: 1.0, paneRim: true, bodyRim: true, sheen: 0.22)
        }
    }
}

/// Apple-style continuous-corner ("squircle") rounded rect.
/// Corner coefficients from the reverse-engineered iOS 7+/Big Sur shape.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / 1.52866483)
    // One corner as (a, b): a = distance from the vertical edge, b = from the
    // horizontal edge, traversed from the incoming edge to the outgoing edge.
    typealias P = (CGFloat, CGFloat)
    let start: P = (1.52866483, 0)
    let ops: [(to: P, c1: P?, c2: P?)] = [
        ((0.66993427, 0.06549600), (1.08849323, 0), (0.86840689, 0)),
        ((0.63149399, 0.07491100), nil, nil),
        ((0.07491176, 0.63149399), (0.37282392, 0.16905899), (0.16906013, 0.37282401)),
        ((0, 1.52866483), (0, 0.86840701), (0, 1.08849299)),
    ]
    let corners: [(P) -> CGPoint] = [
        { p in CGPoint(x: rect.maxX - p.0 * r, y: rect.minY + p.1 * r) }, // top-right
        { p in CGPoint(x: rect.maxX - p.1 * r, y: rect.maxY - p.0 * r) }, // bottom-right
        { p in CGPoint(x: rect.minX + p.0 * r, y: rect.maxY - p.1 * r) }, // bottom-left
        { p in CGPoint(x: rect.minX + p.1 * r, y: rect.minY + p.0 * r) }, // top-left
    ]
    let path = CGMutablePath()
    for (index, map) in corners.enumerated() {
        if index == 0 { path.move(to: map(start)) } else { path.addLine(to: map(start)) }
        for op in ops {
            if let c1 = op.c1, let c2 = op.c2 {
                path.addCurve(to: map(op.to), control1: map(c1), control2: map(c2))
            } else {
                path.addLine(to: map(op.to))
            }
        }
    }
    path.closeSubpath()
    return path
}

// MARK: - Static (baked glass) renderer

func renderIcon(pixels px: Int, palette p: Palette) -> CGImage {
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    let k = CGFloat(px) / Design.canvas          // canvas units → device pixels
    let optics = Optics.forPixelSize(px)

    // y-down 1024 canvas, matching the SVG geometry.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: k, y: -k)

    let body = continuousRoundedRect(Design.bodyRect, radius: Design.bodyRadius)

    // 1. Outer drop shadow (shadow params are in device space, y-up).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: black(p.outerShadowAlpha))
    ctx.addPath(body)
    ctx.setFillColor(p.backgroundBottom)
    ctx.fillPath()
    ctx.restoreGState()

    // Everything else is clipped to the body.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    // 2. Background vertical gradient.
    ctx.drawLinearGradient(
        gradient([p.backgroundTop, p.backgroundBottom]),
        start: CGPoint(x: 0, y: Design.bodyRect.minY),
        end: CGPoint(x: 0, y: Design.bodyRect.maxY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // 3. Top-left radial sheen.
    let sheen = optics.sheen * p.sheenScale
    let sheenCenter = CGPoint(x: Design.bodyRect.minX + 0.22 * 824, y: Design.bodyRect.minY + 0.10 * 824)
    ctx.drawRadialGradient(
        gradient([p.sheen(sheen), p.sheen(sheen * 0.35), p.sheen(0)], [0, 0.45, 1]),
        startCenter: sheenCenter, startRadius: 0,
        endCenter: sheenCenter, endRadius: 0.78 * 824,
        options: []
    )

    // Design geometry → body (824 grid inside the 1024 canvas).
    ctx.saveGState()
    ctx.translateBy(x: Design.bodyRect.minX, y: Design.bodyRect.minY)
    ctx.scaleBy(x: 824 / Design.canvas, y: 824 / Design.canvas)
    let s = (824 / Design.canvas) * k              // design units → device pixels

    // 4. Frosted pane.
    let paneAlpha = p.paneAlpha * optics.paneScale
    if paneAlpha > 0 {
        let pane = CGPath(roundedRect: Design.paneRect, cornerWidth: Design.paneRadius,
                          cornerHeight: Design.paneRadius, transform: nil)
        ctx.saveGState()
        ctx.addPath(pane)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([p.ink(paneAlpha * 1.15), p.ink(paneAlpha * 0.85)]),
            start: CGPoint(x: 0, y: Design.paneRect.minY),
            end: CGPoint(x: 0, y: Design.paneRect.maxY),
            options: []
        )
        if optics.paneRim {
            // Hairline inner rim (~1 device px), stronger on top.
            ctx.addPath(pane)
            ctx.setLineWidth(2 / s)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(
                gradient([p.paneRim.top, p.paneRim.bottom]),
                start: CGPoint(x: 0, y: Design.paneRect.minY),
                end: CGPoint(x: 0, y: Design.paneRect.maxY),
                options: []
            )
        }
        ctx.restoreGState()
    }

    // 5. Corner brackets with a soft drop shadow.
    let bracketOutline = Design.bracketsPath().copy(
        strokingWithWidth: Design.bracketWidth * optics.bracketScale,
        lineCap: .round, lineJoin: .round, miterLimit: 10
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 30 * s, color: black(p.bracketShadowAlpha))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(bracketOutline)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([p.bracketTop, p.bracketBottom]),
        start: CGPoint(x: 0, y: 210), end: CGPoint(x: 0, y: 814),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    ctx.restoreGState() // design transform

    // 6. Inner rim on the body (~1 device px), strongest at the top, fading down.
    if optics.bodyRim {
        ctx.saveGState()
        ctx.addPath(body)
        ctx.setLineWidth(2 / k)   // half of it falls inside the clip → 1px
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(
            gradient(p.bodyRim, [0, 0.5, 1]),
            start: CGPoint(x: 0, y: Design.bodyRect.minY),
            end: CGPoint(x: 0, y: Design.bodyRect.maxY),
            options: []
        )
        ctx.restoreGState()
    }

    ctx.restoreGState() // body clip

    // 7. Hairline neutral border straddling the edge (≥ 1 device px at every size),
    //    so a white tile still reads on white Finder / Dock backgrounds.
    if let border = p.bodyBorder {
        ctx.saveGState()
        ctx.addPath(body)
        ctx.setStrokeColor(border)
        ctx.setLineWidth(max(1.0, CGFloat(px) / 512) / k)
        ctx.strokePath()
        ctx.restoreGState()
    }

    return ctx.makeImage()!
}


func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

// MARK: - Icon Composer layer SVGs (full-bleed 1024)
//
// Colours here are only the shape masks' defaults: icon.json overrides each
// layer's fill per appearance (light = black glyph, dark = white glyph).

let paneSVG = """
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect x="352" y="352" width="320" height="320" rx="30" ry="30" fill="#000000"/>
</svg>

"""

let cornersSVG = """
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <g fill="none" stroke="#000000" stroke-width="96" stroke-linecap="round" stroke-linejoin="round">
    <path d="\(Design.topLeftBracketSVG)"/>
    <path d="\(Design.bottomRightBracketSVG)"/>
  </g>
</svg>

"""

// MARK: - Main

let fm = FileManager.default
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fm.createDirectory(at: layerDirURL, withIntermediateDirectories: true)

let entries: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    let url = iconsetURL.appendingPathComponent("\(entry.name).png")
    try writePNG(renderIcon(pixels: entry.px, palette: .light), to: url)
    print("wrote \(url.path.replacingOccurrences(of: repoURL.path + "/", with: "")) (\(entry.px)px, light)")
}

if let previewDirURL {
    try fm.createDirectory(at: previewDirURL, withIntermediateDirectories: true)
    for palette in [Palette.light, Palette.dark] {
        let url = previewDirURL.appendingPathComponent("AppIcon-\(palette.name)-preview-1024.png")
        try writePNG(renderIcon(pixels: 1024, palette: palette), to: url)
        print("wrote \(url.path) (preview)")
    }
}

for legacy in ["corner-anchor.svg", "frame-dashes.svg"] {
    let url = layerDirURL.appendingPathComponent(legacy)
    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
}
try paneSVG.write(to: layerDirURL.appendingPathComponent("pane.svg"), atomically: true, encoding: .utf8)
try cornersSVG.write(to: layerDirURL.appendingPathComponent("corners.svg"), atomically: true, encoding: .utf8)
print("wrote assets/AppIcon.icon/Assets/{pane,corners}.svg")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed (\(iconutil.terminationStatus))\n".data(using: .utf8)!)
    exit(1)
}
print("wrote assets/AppIcon.icns")
