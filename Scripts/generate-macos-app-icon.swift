#!/usr/bin/env swift

import AppKit
import Foundation

/// Generates Kaštan's bitmap app-icon renditions from the artwork used by the running app.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetCatalog = repositoryRoot
    .appendingPathComponent("KastanApp/Resources/Assets.xcassets", isDirectory: true)
let sourceURL = assetCatalog
    .appendingPathComponent("ApplicationArtwork.imageset", isDirectory: true)
    .appendingPathComponent("ApplicationArtwork@2x.png")
let destinationDirectory = assetCatalog
    .appendingPathComponent("AppIcon.appiconset", isDirectory: true)

let renditions = [
    "AppIcon-16.png": 16,
    "AppIcon-16@2x.png": 32,
    "AppIcon-32.png": 32,
    "AppIcon-32@2x.png": 64,
    "AppIcon-128.png": 128,
    "AppIcon-128@2x.png": 256,
    "AppIcon-256.png": 256,
    "AppIcon-256@2x.png": 512,
    "AppIcon-512.png": 512,
    "AppIcon-512@2x.png": 1_024,
]

/// Matches the full-bleed crop in the Icon Composer document at every legacy rendition size.
let artworkScale: CGFloat = 1.3
let artworkVerticalOffset: CGFloat = 20 / 1_024

guard let artwork = NSImage(contentsOf: sourceURL) else {
    throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: sourceURL])
}

/// Renders one opaque, full-bleed asset-catalog size that avoids macOS's gray legacy frame.
func iconData(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let length = CGFloat(size)
    let artworkLength = length * artworkScale
    let artworkBounds = NSRect(
        x: (length - artworkLength) / 2,
        y: (length - artworkLength) / 2 + length * artworkVerticalOffset,
        width: artworkLength,
        height: artworkLength
    )
    let backdrop = NSGradient(
        starting: NSColor(srgbRed: 0.976, green: 0.949, blue: 0.913, alpha: 1),
        ending: NSColor(srgbRed: 0.878, green: 0.794, blue: 0.718, alpha: 1)
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = NSImageInterpolation.high
    backdrop.draw(
        from: NSPoint(x: 0, y: length),
        to: NSPoint(x: length, y: 0),
        options: []
    )
    artwork.draw(
        in: artworkBounds,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(
        using: NSBitmapImageRep.FileType.png,
        properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 1]
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for (filename, size) in renditions {
    try iconData(size: size).write(
        to: destinationDirectory.appendingPathComponent(filename),
        options: .atomic
    )
}
