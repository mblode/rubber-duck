#!/usr/bin/env swift
// installer/make-dmg-bg.swift
// Generates installer/dmg-background.png for create-dmg.
// Run: swift installer/make-dmg-bg.swift
//
// Canvas: 700 × 460 px (1:1 with the 700 × 460 pt Finder window).
// Finder icon positions (used in create-dmg flags, origin = top-left):
//   App icon     → (175, 230)
//   Applications → (525, 230)
// CG origin is bottom-left, so CG y = H − finder_y.
//   App icon CG  → (175, 230)   [symmetric: 460 − 230 = 230]
//   Apps CG      → (525, 230)
//
// Design: clean warm-white, audio waveform as hero, restrained type.
// Palette: #F7F5F0 warm white · #0B0B12 near-black · #1A7EF0 blue accent

import Foundation
import AppKit
import CoreGraphics
import CoreText

// MARK: - Canvas

let W: CGFloat = 700
let H: CGFloat = 460

// MARK: - Helpers

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func black(_ a: CGFloat) -> CGColor { CGColor(gray: 0, alpha: a) }

// MARK: - Context

let cs = CGColorSpaceCreateDeviceRGB()
let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let ctx = CGContext(
    data: nil, width: Int(W), height: Int(H),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bi.rawValue
) else { fatalError("CGContext failed") }
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// MARK: - Layer 1: Warm white background

// Very slight warm tint — avoids the harshness of pure #FFFFFF
ctx.setFillColor(rgb(247, 245, 240))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// Barely perceptible radial vignette: slightly cooler at the very edges
let vigColors = [rgb(247, 245, 240, a: 0), rgb(230, 228, 224, a: 0.5)] as CFArray
let vigLocs: [CGFloat] = [0, 1]
if let vig = CGGradient(colorsSpace: cs, colors: vigColors, locations: vigLocs) {
    let centre = CGPoint(x: W / 2, y: H / 2)
    ctx.saveGState()
    ctx.drawRadialGradient(vig,
                           startCenter: centre, startRadius: 0,
                           endCenter:   centre, endRadius: 420,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: - Layer 2: Sparse noise for paper texture

srand48(17)
for _ in 0..<1500 {
    let a = CGFloat(drand48()) * 0.018 + 0.004
    ctx.setFillColor(black(a))
    ctx.fillEllipse(in: CGRect(
        x: CGFloat(drand48()) * W - 0.5,
        y: CGFloat(drand48()) * H - 0.5,
        width: 1, height: 1
    ))
}

// MARK: - Layer 3: Audio waveform
//
// Vertical bars centred on the icon midline (CG y = 230).
// Two Gaussian peaks: one at the app icon (x = 175), one at Applications (x = 525).
// Tallest bars get the blue accent; everything else is a soft near-black.

let barCount     = 70
let barSpacing: CGFloat = 7        // centre-to-centre
let barWidth:   CGFloat = 2
let totalSpan   = CGFloat(barCount) * barSpacing
let barOriginX  = (W - totalSpan) / 2 + barSpacing / 2
let waveY: CGFloat = H / 2         // CG y (icons are at CG y = 230 = H/2)

let minBarH: CGFloat = 3
let maxBarH: CGFloat = 72

func waveHeight(barIndex: Int) -> CGFloat {
    let cx = barOriginX + CGFloat(barIndex) * barSpacing
    // Two Gaussians: left = app icon, right = Applications folder
    let g1 = exp(-pow((cx - 175) / 70, 2))
    let g2 = exp(-pow((cx - 525) / 60, 2)) * 0.78
    return minBarH + max(g1, g2) * (maxBarH - minBarH)
}

for i in 0..<barCount {
    let h   = waveHeight(barIndex: i)
    let env = (h - minBarH) / (maxBarH - minBarH)   // normalised 0…1
    let cx  = barOriginX + CGFloat(i) * barSpacing

    let rect = CGRect(
        x: cx - barWidth / 2,
        y: waveY - h / 2,
        width: barWidth,
        height: h
    )

    // Blue on the prominent peaks; muted near-black elsewhere
    if env > 0.80 {
        let a = 0.35 + (env - 0.80) / 0.20 * 0.45   // 0.35 … 0.80
        ctx.setFillColor(rgb(26, 126, 240, a: a))     // #1A7EF0
    } else {
        let a = 0.07 + env * 0.14                     // 0.07 … 0.21
        ctx.setFillColor(black(a))
    }

    let r = barWidth / 2
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.fillPath()
}

// MARK: - Layer 4: Typography

func centredText(
    _ text: String,
    fontName: String,
    size: CGFloat,
    colour: CGColor,
    topY: CGFloat          // pt from top of Finder window (more intuitive)
) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, [])
    let x = (W - bounds.width) / 2 - bounds.origin.x

    // Convert top-of-line (Finder coords) to CG baseline
    let cgBaseline = H - topY - bounds.height + (-bounds.origin.y)

    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: x, y: cgBaseline)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// App name — large, thin
centredText(
    "Rubber Duck",
    fontName: "SFProDisplay-Thin",
    size: 28,
    colour: rgb(11, 11, 18, a: 0.88),
    topY: 32
)

// Tagline
centredText(
    "Voice coding agent for macOS",
    fontName: "SFProDisplay-Ultralight",
    size: 13,
    colour: black(0.32),
    topY: 66
)

// "drag to install" — bottom, very quiet
centredText(
    "drag to install",
    fontName: "SFProDisplay-Thin",
    size: 11,
    colour: black(0.22),
    topY: 418
)

// MARK: - Write PNG

guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
try png.write(to: URL(fileURLWithPath: "installer/dmg-background.png"))
print("✓ installer/dmg-background.png  \(Int(W))×\(Int(H)) px")
