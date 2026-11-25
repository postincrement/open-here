import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("ChromeLauncher/Resources/Assets.xcassets", isDirectory: true)

func png(pixels: Int, points: CGFloat, draw: (NSRect) -> Void) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "icons", code: 1)
    }
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: points, height: points).fill()
    draw(NSRect(x: 0, y: 0, width: points, height: points))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icons", code: 2)
    }
    return data
}

func drawMenuIcon(in rect: NSRect) {
    let inset = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.16)
    let window = NSBezierPath(roundedRect: inset, xRadius: rect.width * 0.14, yRadius: rect.width * 0.14)
    window.lineWidth = max(1.1, rect.width * 0.075)
    window.lineJoinStyle = .round
    NSColor.black.setStroke()
    window.stroke()

    let barY = inset.maxY - inset.height * 0.28
    let bar = NSBezierPath()
    bar.move(to: NSPoint(x: inset.minX + inset.width * 0.16, y: barY))
    bar.line(to: NSPoint(x: inset.maxX - inset.width * 0.16, y: barY))
    bar.lineWidth = max(1, rect.width * 0.06)
    bar.stroke()

    let plus = NSBezierPath()
    let center = NSPoint(x: inset.midX, y: inset.minY + inset.height * 0.36)
    let arm = inset.width * 0.2
    plus.move(to: NSPoint(x: center.x - arm, y: center.y))
    plus.line(to: NSPoint(x: center.x + arm, y: center.y))
    plus.move(to: NSPoint(x: center.x, y: center.y - arm))
    plus.line(to: NSPoint(x: center.x, y: center.y + arm))
    plus.lineWidth = max(1.2, rect.width * 0.08)
    plus.lineCapStyle = .round
    plus.stroke()
}

func drawAppIcon(in rect: NSRect) {
    let colors = [
        NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.78, alpha: 1)
    ]
    if let gradient = NSGradient(colors: colors) {
        gradient.draw(in: rect, angle: -90)
    }

    let card = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.22)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: rect.width * 0.07, yRadius: rect.width * 0.07)
    NSGraphicsContext.saveGraphicsState()
    NSColor.white.setFill()
    cardPath.fill()
    cardPath.addClip()
    let bar = NSRect(x: card.minX, y: card.maxY - card.height * 0.22, width: card.width, height: card.height * 0.22)
    NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.98, alpha: 1).setFill()
    bar.fill()
    if rect.width >= 64 {
        let dot = rect.width * 0.018
        let y = bar.midY - dot / 2
        for index in 0..<3 {
            let x = card.minX + card.width * 0.1 + CGFloat(index) * dot * 2.3
            NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.82, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    let plus = NSBezierPath()
    let center = NSPoint(x: card.midX, y: card.minY + card.height * 0.38)
    let arm = card.width * 0.18
    plus.move(to: NSPoint(x: center.x - arm, y: center.y))
    plus.line(to: NSPoint(x: center.x + arm, y: center.y))
    plus.move(to: NSPoint(x: center.x, y: center.y - arm))
    plus.line(to: NSPoint(x: center.x, y: center.y + arm))
    plus.lineWidth = max(2, rect.width * 0.035)
    plus.lineCapStyle = .round
    NSColor(calibratedRed: 0.13, green: 0.39, blue: 0.82, alpha: 1).setStroke()
    plus.stroke()

    let badgeSide = rect.width * 0.28
    let badge = NSRect(
        x: rect.maxX - badgeSide - rect.width * 0.12,
        y: rect.minY + rect.height * 0.12,
        width: badgeSide,
        height: badgeSide
    )
    NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge).fill()
    let badgePlus = NSBezierPath()
    let badgeArm = badge.width * 0.22
    badgePlus.move(to: NSPoint(x: badge.midX - badgeArm, y: badge.midY))
    badgePlus.line(to: NSPoint(x: badge.midX + badgeArm, y: badge.midY))
    badgePlus.move(to: NSPoint(x: badge.midX, y: badge.midY - badgeArm))
    badgePlus.line(to: NSPoint(x: badge.midX, y: badge.midY + badgeArm))
    badgePlus.lineWidth = max(2, rect.width * 0.028)
    badgePlus.lineCapStyle = .round
    NSColor.white.setStroke()
    badgePlus.stroke()
}

let menuSet = assets.appendingPathComponent("MenuBarIcon.imageset", isDirectory: true)
let iconSet = assets.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: menuSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let menu1x = try png(pixels: 18, points: 18, draw: drawMenuIcon)
let menu2x = try png(pixels: 36, points: 18, draw: drawMenuIcon)
try menu1x.write(to: menuSet.appendingPathComponent("MenuBarIcon.png"))
try menu2x.write(to: menuSet.appendingPathComponent("MenuBarIcon@2x.png"))

let menuContents = """
{
  "images" : [
    {
      "filename" : "MenuBarIcon.png",
      "idiom" : "mac",
      "scale" : "1x"
    },
    {
      "filename" : "MenuBarIcon@2x.png",
      "idiom" : "mac",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
"""
try menuContents.write(to: menuSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let iconSizes: [(String, Int)] = [
    ("16", 16),
    ("16@2x", 32),
    ("32", 32),
    ("32@2x", 64),
    ("128", 128),
    ("128@2x", 256),
    ("256", 256),
    ("256@2x", 512),
    ("512", 512),
    ("512@2x", 1024)
]
var iconEntries: [String] = []
for (name, pixels) in iconSizes {
    let data = try png(pixels: pixels, points: CGFloat(pixels), draw: drawAppIcon)
    let filename = "AppIcon-\(name).png"
    try data.write(to: iconSet.appendingPathComponent(filename))
    let scale = name.contains("@2x") ? "2x" : "1x"
    let point = name.replacingOccurrences(of: "@2x", with: "")
    iconEntries.append("""
    {
      "filename" : "\(filename)",
      "idiom" : "mac",
      "scale" : "\(scale)",
      "size" : "\(point)x\(point)"
    }
""")
}

let iconContents = """
{
  "images" : [
\(iconEntries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try iconContents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try rootContents.write(to: assets.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print(assets.path)
