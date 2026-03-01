#!/usr/bin/env swift
// installer/make-dmg-bg.swift
// Generates installer/dmg-background.png for create-dmg.
// Run: swift installer/make-dmg-bg.swift
// Output: installer/dmg-background.png  (1400 × 920 px = 2× retina for 700 × 460 pt window)

import Foundation
import AppKit
import CoreGraphics
import CoreText

// MARK: - Canvas constants (all in PNG pixels, CG origin = bottom-left)

let W: CGFloat = 1400
let H: CGFloat = 920

// Finder icon centres (pt) × 2 → PNG pixels
// App icon at Finder (175, 230) → PNG (350, 460)
// Applications at  Finder (525, 230) → PNG (1050, 460)
let appCenter  = CGPoint(x: 350,  y: 460)
let appsCenter = CGPoint(x: 1050, y: 460)

// MARK: - Helpers

func hex(_ h: UInt32, a: CGFloat = 1) -> CGColor {
    let r = CGFloat((h >> 16) & 0xFF) / 255
    let g = CGFloat((h >> 8)  & 0xFF) / 255
    let b = CGFloat( h        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: a)
}

func white(_ a: CGFloat) -> CGColor { CGColor(gray: 1, alpha: a) }

// MARK: - Setup bitmap context

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let ctx = CGContext(
    data: nil,
    width:  Int(W),
    height: Int(H),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else { fatalError("Could not create CGContext") }

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// MARK: - Layer 1: Dark gradient background

let gradColors = [hex(0x0D0D12), hex(0x060608)] as CFArray
let gradLocations: [CGFloat] = [0, 1]
guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradColors,
    locations: gradLocations
) else { fatalError("Could not create gradient") }

ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: W / 2, y: H),
    end:   CGPoint(x: W / 2, y: 0),
    options: []
)

// MARK: - Layer 2: Dot grid

let dotSpacing: CGFloat = 40
let dotRadius:  CGFloat = 1.2
ctx.setFillColor(white(0.03))

var x: CGFloat = dotSpacing / 2
while x < W {
    var y: CGFloat = dotSpacing / 2
    while y < H {
        ctx.fillEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius,
                                   width: dotRadius * 2, height: dotRadius * 2))
        y += dotSpacing
    }
    x += dotSpacing
}

// MARK: - Layer 3 & 4: Radial glows

func drawRadialGlow(ctx: CGContext, centre: CGPoint, radius: CGFloat, maxAlpha: CGFloat) {
    let glowColors = [white(maxAlpha), white(0)] as CFArray
    let locs: [CGFloat] = [0, 1]
    guard let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: locs) else { return }
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                               width: radius * 2, height: radius * 2))
    ctx.clip()
    ctx.drawRadialGradient(glow,
                           startCenter: centre, startRadius: 0,
                           endCenter:   centre, endRadius: radius,
                           options: [])
    ctx.restoreGState()
}

drawRadialGlow(ctx: ctx, centre: appCenter,  radius: 220, maxAlpha: 0.06)
drawRadialGlow(ctx: ctx, centre: appsCenter, radius: 180, maxAlpha: 0.04)

// MARK: - Layer 5: Pulse rings

let pulseRadii: [CGFloat] = [90, 135, 180, 225, 270]
let pulseAlphas: [CGFloat] = [0.13, 0.10, 0.07, 0.05, 0.03]

for (idx, radius) in pulseRadii.enumerated() {
    ctx.setStrokeColor(white(pulseAlphas[idx]))
    ctx.setLineWidth(1.5)
    ctx.addEllipse(in: CGRect(x: appCenter.x - radius, y: appCenter.y - radius,
                               width: radius * 2, height: radius * 2))
    ctx.strokePath()
}

// MARK: - Layer 6: Whisper arcs (3 short S-curves to the right of app icon)

let arcAlphas: [CGFloat] = [0.18, 0.11, 0.06]
let arcOffsets: [CGFloat] = [0, 18, -18]

for (idx, alpha) in arcAlphas.enumerated() {
    let startX = appCenter.x + 80
    let startY = appCenter.y + arcOffsets[idx]
    let endX   = appCenter.x + 160
    let endY   = appCenter.y - arcOffsets[idx]
    let cpX    = appCenter.x + 120
    let cpY    = appCenter.y + arcOffsets[idx] * 2.5

    ctx.beginPath()
    ctx.move(to: CGPoint(x: startX, y: startY))
    ctx.addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: cpX, y: cpY))
    ctx.setStrokeColor(white(alpha))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
}

// MARK: - Layer 7: Center divider

ctx.setStrokeColor(white(0.06))
ctx.setLineWidth(1)
ctx.move(to: CGPoint(x: W / 2, y: 80))
ctx.addLine(to: CGPoint(x: W / 2, y: H - 80))
ctx.strokePath()

// MARK: - Layer 8: Curved arrow (app → Applications)
// Quadratic Bezier from right of app icon to left of apps icon,
// bowing downward (in CG coords = upward on screen).

let arrowStart   = CGPoint(x: appCenter.x  + 120, y: appCenter.y - 15)
let arrowEnd     = CGPoint(x: appsCenter.x - 120, y: appsCenter.y - 15)
let arrowControl = CGPoint(x: W / 2, y: appCenter.y - 130)

ctx.beginPath()
ctx.move(to: arrowStart)
ctx.addQuadCurve(to: arrowEnd, control: arrowControl)
ctx.setStrokeColor(white(0.55))
ctx.setLineWidth(2.0)
ctx.strokePath()

// Arrowhead at arrowEnd
let headLen:   CGFloat = 14
let headAngle: CGFloat = 0.4  // radians half-spread

// Tangent at end of quadratic Bezier: derivative = 2*(1-t)*(control-start) + 2*t*(end-control) at t=1
// = 2 * (end - control)
let tangentX = arrowEnd.x - arrowControl.x
let tangentY = arrowEnd.y - arrowControl.y
let tangentAngle = atan2(tangentY, tangentX)

let wing1 = CGPoint(
    x: arrowEnd.x - headLen * cos(tangentAngle - headAngle),
    y: arrowEnd.y - headLen * sin(tangentAngle - headAngle)
)
let wing2 = CGPoint(
    x: arrowEnd.x - headLen * cos(tangentAngle + headAngle),
    y: arrowEnd.y - headLen * sin(tangentAngle + headAngle)
)

ctx.beginPath()
ctx.move(to: arrowEnd)
ctx.addLine(to: wing1)
ctx.addLine(to: wing2)
ctx.closePath()
ctx.setFillColor(white(0.55))
ctx.fillPath()

// MARK: - Layer 9: "drag to install" label
// Displayed y ≈ 350 pt from top = CG y ≈ H - 350*2 = 220

func drawCentredText(
    ctx: CGContext,
    text: String,
    font: CTFont,
    color: CGColor,
    centreY: CGFloat   // CG bottom-up Y of the text baseline
) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attrStr)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    let x = (W - bounds.width) / 2 - bounds.origin.x
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: x, y: centreY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// "drag to install" — small condensed, wide tracking, low opacity
let dragFont = CTFontCreateWithName("SFProDisplay-Thin" as CFString, 22, nil)
let dragColor = white(0.30)
let dragLabel = "drag to install"
drawCentredText(ctx: ctx, text: dragLabel, font: dragFont, color: dragColor, centreY: 220)

// MARK: - Layer 10: "RubberDuck" title
// Displayed y ≈ 48 pt from top → CG y ≈ H - 48*2 = 824

let titleFont  = CTFontCreateWithName("SFProDisplay-Thin" as CFString, 48, nil)
let titleColor = white(0.85)
drawCentredText(ctx: ctx, text: "RubberDuck", font: titleFont, color: titleColor, centreY: 824)

// MARK: - Layer 11: Tagline
// Displayed y ≈ 72 pt from top → CG y ≈ H - 72*2 = 776

let tagFont  = CTFontCreateWithName("SFProDisplay-Ultralight" as CFString, 26, nil)
let tagColor = white(0.28)
drawCentredText(ctx: ctx, text: "Dictate, transcribe, command.", font: tagFont, color: tagColor, centreY: 770)

// MARK: - Write PNG

guard let cgImage = ctx.makeImage() else { fatalError("Could not create image") }
let image = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = image.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

let outputURL = URL(fileURLWithPath: "installer/dmg-background.png")
try pngData.write(to: outputURL)
print("✓ installer/dmg-background.png written (\(Int(W))×\(Int(H)) px)")
