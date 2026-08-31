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

func maximumComponentDifference(in colors: [NSColor]) -> CGFloat {
    guard let reference = colors.first else {
        return .infinity
    }
    return colors.dropFirst().reduce(0) { difference, color in
        max(
            difference,
            abs(color.redComponent - reference.redComponent),
            abs(color.greenComponent - reference.greenComponent),
            abs(color.blueComponent - reference.blueComponent)
        )
    }
}

func matchingPixelBounds(
    of image: NSBitmapImageRep,
    xRange: Range<Int>,
    yRange: Range<Int>,
    matching predicate: (NSColor) -> Bool
) -> (count: Int, minimumX: Int, maximumX: Int, minimumY: Int, maximumY: Int)? {
    var count = 0
    var minimumX = image.pixelsWide
    var maximumX = 0
    var minimumY = image.pixelsHigh
    var maximumY = 0

    for y in yRange {
        for x in xRange {
            guard let sample = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                  predicate(sample) else {
                continue
            }
            count += 1
            minimumX = min(minimumX, x)
            maximumX = max(maximumX, x)
            minimumY = min(minimumY, y)
            maximumY = max(maximumY, y)
        }
    }

    guard count > 0 else {
        return nil
    }
    return (count, minimumX, maximumX, minimumY, maximumY)
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
let iconGroups = iconDocument["groups"] as? [[String: Any]] ?? []
precondition(iconGroups.count == 1, "The app icon must use one self-contained chestnut group")
let iconGroup = iconGroups[0]
let iconShadow = iconGroup["shadow"] as? [String: Any]
let iconTranslucency = iconGroup["translucency"] as? [String: Any]
precondition(
    (iconShadow?["opacity"] as? NSNumber)?.doubleValue == 0
        && iconGroup["specular"] as? Bool == false
        && iconTranslucency?["enabled"] as? Bool == false
        && (iconTranslucency?["value"] as? NSNumber)?.doubleValue == 0,
    "Icon Composer must not lighten the shell frame with its own shadow, specular, or translucent material"
)
let iconComposerArtwork = iconComposer
    .appendingPathComponent("Assets", isDirectory: true)
    .appendingPathComponent("ApplicationArtwork.png")
let iconLayers = iconGroups.flatMap { group in
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
    color(of: iconComposerImage, x: 0.50, y: 0.025),
    color(of: iconComposerImage, x: 0.975, y: 0.50),
    color(of: iconComposerImage, x: 0.50, y: 0.975),
    color(of: iconComposerImage, x: 0.025, y: 0.50),
].compactMap { $0 }
precondition(
    frameSamples.count == 4
        && frameSamples.allSatisfy(isDarkChestnut)
        && maximumComponentDifference(in: iconComposerCorners + frameSamples) <= 0.01,
    "The shell contour must form one uniformly dark frame through every corner and edge"
)
let surfaceSamples = [
    color(of: iconComposerImage, x: 0.50, y: 0.065),
    color(of: iconComposerImage, x: 0.935, y: 0.50),
    color(of: iconComposerImage, x: 0.50, y: 0.935),
    color(of: iconComposerImage, x: 0.065, y: 0.50),
].compactMap { $0 }
precondition(
    surfaceSamples.count == 4 && surfaceSamples.allSatisfy(isChestnutSurface),
    "The chestnut surface must leave a slim dark frame that remains visible beneath system lighting"
)

let ovalBounds = matchingPixelBounds(
    of: iconComposerImage,
    xRange: 0..<430,
    yRange: 500..<1_024
) { sample in
    sample.greenComponent > 0.62 && sample.blueComponent > 0.38
}
precondition(
    ovalBounds.map { bounds in
        bounds.count >= 50_000
            && bounds.maximumX - bounds.minimumX >= 280
            && bounds.maximumY - bounds.minimumY >= 300
    } == true,
    "The lower-left cut must retain a complete, clearly visible oval instead of being cropped away"
)
let pointBounds = matchingPixelBounds(
    of: iconComposerImage,
    xRange: 500..<1_024,
    yRange: 0..<400
) { sample in
    sample.greenComponent > 0.50 && sample.blueComponent > 0.25
}
precondition(
    pointBounds.map { bounds in
        bounds.count >= 1_400
            && bounds.maximumX >= 930
            && bounds.minimumY <= 65
            && bounds.maximumX - bounds.minimumX >= 350
    } == true,
    "The upper-right grain and pointed tip must extend outward into the rectangular icon's corner"
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
