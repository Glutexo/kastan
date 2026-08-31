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

let sourceData = try Data(contentsOf: sourceURL)
guard let sourceBitmap = NSBitmapImageRep(data: sourceData) else {
    throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: sourceURL])
}

let masterSize = 1_024
let angleCount = 4_096
let fullTurn = 2 * CGFloat.pi
let frameInset: CGFloat = 0.028
let innerCornerRadius: CGFloat = 0.194
let frameColor = NSColor(deviceRed: 0.14, green: 0.03, blue: 0.01, alpha: 1)
let sourceCenter = NSPoint(
    x: CGFloat(sourceBitmap.pixelsWide) * 0.52,
    y: CGFloat(sourceBitmap.pixelsHigh) * 0.52
)

func angleIndex(_ angle: CGFloat) -> (lower: Int, upper: Int, fraction: CGFloat) {
    var normalized = angle / fullTurn
    if normalized < 0 {
        normalized += 1
    }
    let position = normalized * CGFloat(angleCount)
    let lower = Int(position.rounded(.down)) % angleCount
    return (lower, (lower + 1) % angleCount, position - CGFloat(lower))
}

func radius(at angle: CGFloat, in radii: [CGFloat]) -> CGFloat {
    let index = angleIndex(angle)
    return radii[index.lower] * (1 - index.fraction)
        + radii[index.upper] * index.fraction
}

/// Finds the original outer contour in every direction so no characteristic part is cropped away.
func sourceBoundaryRadii() -> [CGFloat] {
    let maximumDistance = CGFloat(max(sourceBitmap.pixelsWide, sourceBitmap.pixelsHigh))
    return (0..<angleCount).map { index in
        let angle = fullTurn * CGFloat(index) / CGFloat(angleCount)
        let directionX = cos(angle)
        let directionY = sin(angle)
        var lastOpaqueDistance: CGFloat = 0
        var distance: CGFloat = 0

        while distance <= maximumDistance {
            let x = Int((sourceCenter.x + directionX * distance).rounded())
            let y = Int((sourceCenter.y + directionY * distance).rounded())
            guard x >= 0, x < sourceBitmap.pixelsWide,
                  y >= 0, y < sourceBitmap.pixelsHigh else {
                break
            }
            let alpha = sourceBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            if alpha >= 0.05 {
                lastOpaqueDistance = distance
            } else if lastOpaqueDistance > 0 {
                break
            }
            distance += 1
        }
        return lastOpaqueDistance
    }
}

func isInsideShellSurface(x: CGFloat, y: CGFloat) -> Bool {
    let minimum = frameInset
    let maximum = 1 - frameInset
    guard x >= minimum, x <= maximum, y >= minimum, y <= maximum else {
        return false
    }

    let cornerMinimum = minimum + innerCornerRadius
    let cornerMaximum = maximum - innerCornerRadius
    if x >= cornerMinimum, x <= cornerMaximum {
        return true
    }
    if y >= cornerMinimum, y <= cornerMaximum {
        return true
    }

    let centerX = x < cornerMinimum ? cornerMinimum : cornerMaximum
    let centerY = y < cornerMinimum ? cornerMinimum : cornerMaximum
    let deltaX = x - centerX
    let deltaY = y - centerY
    return deltaX * deltaX + deltaY * deltaY <= innerCornerRadius * innerCornerRadius
}

/// Finds the matching rounded-rectangle boundary for the same set of directions.
func targetBoundaryRadii() -> [CGFloat] {
    (0..<angleCount).map { index in
        let angle = fullTurn * CGFloat(index) / CGFloat(angleCount)
        let directionX = cos(angle)
        let directionY = sin(angle)
        var lower: CGFloat = 0
        var upper: CGFloat = 1

        for _ in 0..<16 {
            let candidate = (lower + upper) / 2
            if isInsideShellSurface(
                x: 0.5 + directionX * candidate,
                y: 0.5 + directionY * candidate
            ) {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return lower
    }
}

let originalRadii = sourceBoundaryRadii()
let rectangularRadii = targetBoundaryRadii()

/// Replaces only the pale source apex with neighboring shell color so no separate point remains in the rectangle.
func opaqueSourceColor(x: CGFloat, y: CGFloat) -> NSColor {
    let sourceX = min(sourceBitmap.pixelsWide - 1, max(0, Int(x.rounded())))
    let sourceY = min(sourceBitmap.pixelsHigh - 1, max(0, Int(y.rounded())))
    guard let source = sourceBitmap.colorAt(x: sourceX, y: sourceY)?.usingColorSpace(.deviceRGB) else {
        return frameColor
    }
    var red = source.redComponent
    var green = source.greenComponent
    var blue = source.blueComponent
    if sourceX >= Int(CGFloat(sourceBitmap.pixelsWide) * 0.68),
       sourceY <= Int(CGFloat(sourceBitmap.pixelsHigh) * 0.26),
       blue > 0.15 {
        let replacementY = min(
            sourceBitmap.pixelsHigh - 1,
            sourceY + Int(CGFloat(sourceBitmap.pixelsHigh) * 0.16)
        )
        if let replacement = sourceBitmap.colorAt(x: sourceX, y: replacementY)?
            .usingColorSpace(.deviceRGB) {
            let blend = min(1, max(0, (blue - 0.15) / 0.25))
            red = red * (1 - blend) + replacement.redComponent * blend
            green = green * (1 - blend) + replacement.greenComponent * blend
            blue = blue * (1 - blend) + replacement.blueComponent * blend
        }
    }
    let alpha = source.alphaComponent
    return NSColor(
        deviceRed: red * alpha + frameColor.redComponent * (1 - alpha),
        green: green * alpha + frameColor.greenComponent * (1 - alpha),
        blue: blue * alpha + frameColor.blueComponent * (1 - alpha),
        alpha: 1
    )
}

/// Maps the complete freeform chestnut radially into the framed rectangle without adding a backing layer.
func masterIconData() throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: masterSize,
        pixelsHigh: masterSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    for y in 0..<masterSize {
        for x in 0..<masterSize {
            let normalizedX = (CGFloat(x) + 0.5) / CGFloat(masterSize)
            let normalizedY = (CGFloat(y) + 0.5) / CGFloat(masterSize)
            let deltaX = normalizedX - 0.5
            let deltaY = normalizedY - 0.5
            let angle = atan2(deltaY, deltaX)
            let targetRadius = radius(at: angle, in: rectangularRadii)
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

            guard distance < targetRadius else {
                bitmap.setColor(frameColor, atX: x, y: y)
                continue
            }

            let sourceRadius = radius(at: angle, in: originalRadii)
            let radialFraction = min(0.998, distance / targetRadius)
            let directionX = cos(angle)
            let directionY = sin(angle)
            bitmap.setColor(
                opaqueSourceColor(
                    x: sourceCenter.x + directionX * sourceRadius * radialFraction,
                    y: sourceCenter.y + directionY * sourceRadius * radialFraction
                ),
                atX: x,
                y: y
            )
        }
    }

    guard let data = bitmap.representation(
        using: NSBitmapImageRep.FileType.png,
        properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 1]
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

func renditionData(size: Int, masterImage: NSImage) throws -> Data {
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

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    masterImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(
        using: .png,
        properties: [.compressionFactor: 1]
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

let masterData = try masterIconData()
guard let masterImage = NSImage(data: masterData) else {
    throw CocoaError(.fileReadCorruptFile)
}
try masterData.write(to: iconComposerArtworkURL, options: .atomic)

for (filename, size) in renditions {
    let data = size == masterSize ? masterData : try renditionData(size: size, masterImage: masterImage)
    try data.write(
        to: destinationDirectory.appendingPathComponent(filename),
        options: .atomic
    )
}
