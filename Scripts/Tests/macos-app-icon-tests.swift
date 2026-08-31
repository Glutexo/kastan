import AppKit
import Foundation

/// Protects Kaštan's full-bleed chestnut bundle icon and the complete transparent runtime artwork.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetCatalog = repositoryRoot
    .appendingPathComponent("KastanApp/Resources/Assets.xcassets", isDirectory: true)
let iconComposer = repositoryRoot
    .appendingPathComponent("KastanApp/Resources/AppIcon.icon", isDirectory: true)

func pngFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "png" }
}

func bitmap(at url: URL) throws -> NSBitmapImageRep {
    guard let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
    }
    return image
}

func jsonDictionary(at url: URL) throws -> [String: Any] {
    guard let dictionary = try JSONSerialization.jsonObject(
        with: Data(contentsOf: url)
    ) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
    }
    return dictionary
}

func cornerAlphas(of image: NSBitmapImageRep) -> [CGFloat] {
    let corners = [
        (0, 0),
        (image.pixelsWide - 1, 0),
        (0, image.pixelsHigh - 1),
        (image.pixelsWide - 1, image.pixelsHigh - 1),
    ]
    return corners.compactMap { image.colorAt(x: $0.0, y: $0.1)?.alphaComponent }
}

func isFullyOpaque(_ image: NSBitmapImageRep) -> Bool {
    for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide
        where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) < 0.999 {
            return false
        }
    }
    return true
}

func color(of image: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> NSColor? {
    image.colorAt(
        x: min(image.pixelsWide - 1, Int(CGFloat(image.pixelsWide) * x)),
        y: min(image.pixelsHigh - 1, Int(CGFloat(image.pixelsHigh) * y))
    )?.usingColorSpace(.sRGB)
}

/// Recognizes the dark brown shell contour that must be the icon's only outer edge.
func isDarkChestnut(_ color: NSColor) -> Bool {
    color.redComponent <= 0.36
        && color.redComponent - color.greenComponent >= 0.08
        && color.greenComponent >= color.blueComponent
}

/// Recognizes the brighter shell surface immediately inside the continuous dark frame.
func isChestnutSurface(_ color: NSColor) -> Bool {
    color.redComponent >= 0.45
        && color.redComponent - color.greenComponent >= 0.20
        && color.greenComponent - color.blueComponent >= 0.10
}

let iconDocumentURL = iconComposer.appendingPathComponent("icon.json")
let iconDocument = try jsonDictionary(at: iconDocumentURL)
let automaticGradient = (iconDocument["fill"] as? [String: Any])?["automatic-gradient"] as? String
precondition(
    automaticGradient == "extended-srgb:0.00000,0.00000,0.00000,0.00000",
    "The inactive Icon Composer fill must not add a separate backdrop behind the full-bleed chestnut"
)
let iconComposerArtwork = iconComposer
    .appendingPathComponent("Assets", isDirectory: true)
    .appendingPathComponent("ApplicationArtwork.png")
let iconLayers = (iconDocument["groups"] as? [[String: Any]] ?? []).flatMap { group in
    group["layers"] as? [[String: Any]] ?? []
}
let artworkLayer = iconLayers.first {
    $0["image-name"] as? String == iconComposerArtwork.lastPathComponent
}
precondition(
    artworkLayer != nil,
    "The Icon Composer document must render Kaštan's application artwork"
)
let artworkPosition = artworkLayer?["position"] as? [String: Any]
let artworkScale = (artworkPosition?["scale"] as? NSNumber)?.doubleValue
let artworkTranslation = artworkPosition?["translation-in-points"] as? [NSNumber]
precondition(
    artworkScale.map { abs($0 - 1) <= 0.000_1 } == true
        && artworkTranslation?.count == 2
        && abs(artworkTranslation?[0].doubleValue ?? .infinity) <= 0.000_1
        && abs(artworkTranslation?[1].doubleValue ?? .infinity) <= 0.000_1,
    "The Icon Composer document must preserve the precomposed chestnut silhouette"
)

let iconComposerImage = try bitmap(at: iconComposerArtwork)
precondition(
    iconComposerImage.pixelsWide == 1_024 && iconComposerImage.pixelsHigh == 1_024,
    "Icon Composer artwork must be 1024 × 1024 pixels"
)
precondition(
    isFullyOpaque(iconComposerImage),
    "Icon Composer artwork must cover the complete system mask so no system plate can appear behind it"
)
let iconComposerCorners = [
    color(of: iconComposerImage, x: 0, y: 0),
    color(of: iconComposerImage, x: 0.999, y: 0),
    color(of: iconComposerImage, x: 0, y: 0.999),
    color(of: iconComposerImage, x: 0.999, y: 0.999),
].compactMap { $0 }
precondition(
    iconComposerCorners.count == 4 && iconComposerCorners.allSatisfy(isDarkChestnut),
    "The shell's dark contour must form every outer corner of the Finder icon"
)
let frameSamples = [
    color(of: iconComposerImage, x: 0.50, y: 0.015),
    color(of: iconComposerImage, x: 0.985, y: 0.50),
    color(of: iconComposerImage, x: 0.50, y: 0.985),
    color(of: iconComposerImage, x: 0.015, y: 0.50),
].compactMap { $0 }
precondition(
    frameSamples.count == 4 && frameSamples.allSatisfy(isDarkChestnut),
    "The shell contour must form one continuous frame at every edge midpoint"
)
let surfaceSamples = [
    color(of: iconComposerImage, x: 0.50, y: 0.045),
    color(of: iconComposerImage, x: 0.955, y: 0.50),
    color(of: iconComposerImage, x: 0.50, y: 0.955),
    color(of: iconComposerImage, x: 0.045, y: 0.50),
].compactMap { $0 }
precondition(
    surfaceSamples.count == 4 && surfaceSamples.allSatisfy(isChestnutSurface),
    "The shell surface must begin evenly inside every side of the dark frame"
)
let topSurface = color(of: iconComposerImage, x: 0.50, y: 0.045)
let pointHighlight = color(of: iconComposerImage, x: 0.72, y: 0.045)
precondition(
    topSurface.map { surface in
        pointHighlight.map { highlight in
            highlight.greenComponent - surface.greenComponent >= 0.15
        } ?? false
    } == true,
    "The upper highlight must suggest the chestnut point without interrupting the frame"
)

let appIcons = try pngFiles(
    in: assetCatalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
)
let expectedAppIconSizes = [
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
precondition(
    Set(appIcons.map(\.lastPathComponent)) == Set(expectedAppIconSizes.keys),
    "The macOS app icon must provide all ten required renditions"
)

for icon in appIcons {
    let image = try bitmap(at: icon)
    let expectedSize = expectedAppIconSizes[icon.lastPathComponent]!
    precondition(
        image.pixelsWide == expectedSize && image.pixelsHigh == expectedSize,
        "\(icon.lastPathComponent) must be \(expectedSize) × \(expectedSize) pixels"
    )
    precondition(
        isFullyOpaque(image),
        "\(icon.lastPathComponent) must cover its complete system mask"
    )
    let corners = [
        color(of: image, x: 0, y: 0),
        color(of: image, x: 0.999, y: 0),
        color(of: image, x: 0, y: 0.999),
        color(of: image, x: 0.999, y: 0.999),
    ].compactMap { $0 }
    precondition(
        corners.count == 4 && corners.allSatisfy(isDarkChestnut),
        "\(icon.lastPathComponent) must use the shell's dark contour as its complete outer edge"
    )
}

let runtimeArtwork = try pngFiles(
    in: assetCatalog.appendingPathComponent("ApplicationArtwork.imageset", isDirectory: true)
)
let expectedArtworkSizes = [
    "ApplicationArtwork.png": 512,
    "ApplicationArtwork@2x.png": 1_024,
]
precondition(
    Set(runtimeArtwork.map(\.lastPathComponent)) == Set(expectedArtworkSizes.keys),
    "Runtime artwork must provide standard and Retina renditions"
)

for artwork in runtimeArtwork {
    let image = try bitmap(at: artwork)
    let expectedSize = expectedArtworkSizes[artwork.lastPathComponent]!
    precondition(
        image.pixelsWide == expectedSize && image.pixelsHigh == expectedSize,
        "\(artwork.lastPathComponent) must be \(expectedSize) × \(expectedSize) pixels"
    )
    let alphas = cornerAlphas(of: image)
    precondition(
        alphas.count == 4 && alphas.allSatisfy { $0 <= 0.001 },
        "\(artwork.lastPathComponent) must remain transparent for the Dock and app switcher"
    )
}

let iconComposerArtworkData = try Data(contentsOf: iconComposerArtwork)
let largestFallbackArtwork = assetCatalog
    .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
    .appendingPathComponent("AppIcon-512@2x.png")
let largestFallbackArtworkData = try Data(contentsOf: largestFallbackArtwork)
precondition(
    iconComposerArtworkData == largestFallbackArtworkData,
    "Icon Composer and the fallback asset catalog must use the same full-resolution Finder silhouette"
)
