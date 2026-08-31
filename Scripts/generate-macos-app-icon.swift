#!/usr/bin/env swift

import AppKit
import Foundation

/// Reshapes Kaštan's freeform artwork into the self-contained chestnut icon used by Finder and Spotlight.
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
let iconComposerArtworkURL = repositoryRoot
    .appendingPathComponent("KastanApp/Resources/AppIcon.icon/Assets/ApplicationArtwork.png")

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

guard let artwork = NSImage(contentsOf: sourceURL) else {
    throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: sourceURL])
}

/// Uses an opaque portion of the original illustration as the full icon surface, including its cut and highlights.
let artworkCrop = NSRect(
    x: artwork.size.width * 0.175,
    y: artwork.size.height * 0.15,
    width: artwork.size.width * 0.69,
    height: artwork.size.height * 0.645
)

/// Insets the shell surface evenly so the dark outer contour reads as one continuous frame.
func shellSurfacePath(length: CGFloat) -> NSBezierPath {
    let inset = length * 0.03
    return NSBezierPath(
        roundedRect: NSRect(
            x: inset,
            y: inset,
            width: length - 2 * inset,
            height: length - 2 * inset
        ),
        xRadius: length * 0.18,
        yRadius: length * 0.18
    )
}

/// Renders one opaque icon made only from the chestnut surface and its natural dark contour.
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
    let canvas = NSRect(x: 0, y: 0, width: length, height: length)
    let contour = NSGradient(
        starting: NSColor(srgbRed: 0.20, green: 0.045, blue: 0.012, alpha: 1),
        ending: NSColor(srgbRed: 0.075, green: 0.012, blue: 0.004, alpha: 1)
    )!
    let surface = shellSurfacePath(length: length)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = NSImageInterpolation.high
    contour.draw(
        from: NSPoint(x: 0, y: length),
        to: NSPoint(x: length, y: 0),
        options: []
    )
    surface.addClip()
    artwork.draw(
        in: canvas,
        from: artworkCrop,
        operation: .copy,
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

try iconData(size: 1_024).write(to: iconComposerArtworkURL, options: .atomic)

for (filename, size) in renditions {
    try iconData(size: size).write(
        to: destinationDirectory.appendingPathComponent(filename),
        options: .atomic
    )
}
