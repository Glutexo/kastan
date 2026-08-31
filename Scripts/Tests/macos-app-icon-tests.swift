import AppKit
import Foundation

/// Protects Kaštan's full-bleed bundle icon and the complete transparent runtime artwork.
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

/// Samples the visible edge centers where a neutral frame would otherwise surround the artwork.
func middleEdgeColors(of image: NSBitmapImageRep) -> [NSColor] {
    let inset = max(1, image.pixelsWide / 64)
    let edges = [
        (image.pixelsWide / 2, inset),
        (image.pixelsWide / 2, image.pixelsHigh - inset - 1),
        (inset, image.pixelsHigh / 2),
        (image.pixelsWide - inset - 1, image.pixelsHigh / 2),
    ]
    return edges.compactMap {
        image.colorAt(x: $0.0, y: $0.1)?.usingColorSpace(.sRGB)
    }
}

let iconDocumentURL = iconComposer.appendingPathComponent("icon.json")
let iconDocument = try jsonDictionary(at: iconDocumentURL)
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
    artworkScale.map { abs($0 - 1.3) <= 0.000_1 } == true
        && artworkTranslation?.count == 2
        && abs(artworkTranslation?[0].doubleValue ?? .infinity) <= 0.000_1
        && abs((artworkTranslation?[1].doubleValue ?? .infinity) + 20) <= 0.000_1,
    "The Icon Composer artwork must retain its frame-free full-bleed crop"
)

let iconComposerImage = try bitmap(at: iconComposerArtwork)
precondition(
    iconComposerImage.pixelsWide == 1_024 && iconComposerImage.pixelsHigh == 1_024,
    "Icon Composer artwork must be 1024 × 1024 pixels"
)
let iconComposerAlphas = cornerAlphas(of: iconComposerImage)
precondition(
    iconComposerAlphas.count == 4 && iconComposerAlphas.allSatisfy { $0 <= 0.001 },
    "Icon Composer artwork must stay transparent so its backdrop remains independently adaptable"
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
    let alphas = cornerAlphas(of: image)
    precondition(
        alphas.count == 4 && alphas.allSatisfy { $0 >= 0.999 },
        "\(icon.lastPathComponent) must remain opaque so macOS does not add its gray legacy frame"
    )
    let colors = middleEdgeColors(of: image)
    precondition(
        colors.count == 4 && colors.allSatisfy { color in
            return color.redComponent > color.greenComponent
                && color.greenComponent > color.blueComponent
                && color.redComponent - color.blueComponent >= 0.08
        },
        "\(icon.lastPathComponent) must keep chestnut artwork along every visible edge"
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

let retinaRuntimeArtwork = assetCatalog
    .appendingPathComponent("ApplicationArtwork.imageset", isDirectory: true)
    .appendingPathComponent("ApplicationArtwork@2x.png")
let iconComposerArtworkData = try Data(contentsOf: iconComposerArtwork)
let retinaRuntimeArtworkData = try Data(contentsOf: retinaRuntimeArtwork)
precondition(
    iconComposerArtworkData == retinaRuntimeArtworkData,
    "Icon Composer and the running app must use the same full-resolution chestnut artwork"
)
