import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-assets.swift <output-directory>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GPTFlowMonitorAssets", code: 1)
    }
    try png.write(to: url, options: .atomic)
}

func appIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()

    let bounds = NSRect(origin: .zero, size: size)
    NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 28, dy: 28), xRadius: 220, yRadius: 220).fill()

    NSColor(calibratedWhite: 1, alpha: 0.09).setStroke()
    let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 29, dy: 29), xRadius: 219, yRadius: 219)
    border.lineWidth = 4
    border.stroke()

    let cyan = NSColor(calibratedRed: 0.39, green: 0.78, blue: 0.82, alpha: 1)
    cyan.setStroke()

    let topY: CGFloat = 730
    let bottomY: CGFloat = 294
    let left: CGFloat = 350
    let right: CGFloat = 674
    let centerX: CGFloat = 512

    let bars = NSBezierPath()
    bars.lineCapStyle = .round
    bars.lineWidth = 46
    bars.move(to: NSPoint(x: left, y: topY))
    bars.line(to: NSPoint(x: right, y: topY))
    bars.move(to: NSPoint(x: left, y: bottomY))
    bars.line(to: NSPoint(x: right, y: bottomY))
    bars.stroke()

    let glass = NSBezierPath()
    glass.lineCapStyle = .round
    glass.lineJoinStyle = .round
    glass.lineWidth = 42
    glass.move(to: NSPoint(x: left + 28, y: topY - 26))
    glass.curve(
        to: NSPoint(x: centerX, y: 512),
        controlPoint1: NSPoint(x: left + 40, y: 620),
        controlPoint2: NSPoint(x: centerX - 54, y: 560)
    )
    glass.curve(
        to: NSPoint(x: left + 28, y: bottomY + 26),
        controlPoint1: NSPoint(x: centerX - 54, y: 464),
        controlPoint2: NSPoint(x: left + 40, y: 402)
    )
    glass.move(to: NSPoint(x: right - 28, y: topY - 26))
    glass.curve(
        to: NSPoint(x: centerX, y: 512),
        controlPoint1: NSPoint(x: right - 40, y: 620),
        controlPoint2: NSPoint(x: centerX + 54, y: 560)
    )
    glass.curve(
        to: NSPoint(x: right - 28, y: bottomY + 26),
        controlPoint1: NSPoint(x: centerX + 54, y: 464),
        controlPoint2: NSPoint(x: right - 40, y: 402)
    )
    glass.stroke()

    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: 270, y: 700, width: 280, height: 120)).fill()

    image.unlockFocus()
    return image
}

func menuBarIcon() -> NSImage {
    let size = NSSize(width: 30, height: 30)
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor.black.setStroke()
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 2.6
    path.move(to: NSPoint(x: 8, y: 24))
    path.line(to: NSPoint(x: 22, y: 24))
    path.move(to: NSPoint(x: 8, y: 6))
    path.line(to: NSPoint(x: 22, y: 6))
    path.move(to: NSPoint(x: 9.5, y: 22.5))
    path.curve(to: NSPoint(x: 15, y: 15), controlPoint1: NSPoint(x: 10, y: 19), controlPoint2: NSPoint(x: 13, y: 17))
    path.curve(to: NSPoint(x: 9.5, y: 7.5), controlPoint1: NSPoint(x: 13, y: 13), controlPoint2: NSPoint(x: 10, y: 11))
    path.move(to: NSPoint(x: 20.5, y: 22.5))
    path.curve(to: NSPoint(x: 15, y: 15), controlPoint1: NSPoint(x: 20, y: 19), controlPoint2: NSPoint(x: 17, y: 17))
    path.curve(to: NSPoint(x: 20.5, y: 7.5), controlPoint1: NSPoint(x: 17, y: 13), controlPoint2: NSPoint(x: 20, y: 11))
    path.stroke()

    image.unlockFocus()
    return image
}

try writePNG(appIcon(), to: outputDirectory.appendingPathComponent("AppIcon-1024.png"))
try writePNG(menuBarIcon(), to: outputDirectory.appendingPathComponent("MenuBarHourglassTemplate.png"))
