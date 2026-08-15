import AppKit
import Foundation

/// Protects Kaštan's layered bundle icon, its bitmap renditions, and the transparent runtime artwork.
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

/// Decodes Icon Composer's extended-sRGB notation so the product backdrop remains testable.
func extendedSRGBComponents(in value: String) -> [Double]? {
    let prefix = "extended-srgb:"
    guard value.hasPrefix(prefix) else { return nil }
    let components = value.dropFirst(prefix.count).split(separator: ",")
    guard components.count == 4 else { return nil }
    let values = components.compactMap { Double($0) }
    return values.count == 4 ? values : nil
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

/// Reads the icon corners in a stable color space so the intended warm backdrop remains testable.
func cornerColors(of image: NSBitmapImageRep) -> [NSColor] {
    let corners = [
        (0, 0),
        (image.pixelsWide - 1, 0),
        (0, image.pixelsHigh - 1),
        (image.pixelsWide - 1, image.pixelsHigh - 1),
    ]
    return corners.compactMap {
        image.colorAt(x: $0.0, y: $0.1)?.usingColorSpace(.sRGB)
    }
}

let iconDocumentURL = iconComposer.appendingPathComponent("icon.json")
let iconDocument = try jsonDictionary(at: iconDocumentURL)
let automaticGradient = (iconDocument["fill"] as? [String: Any])?["automatic-gradient"] as? String
let gradientComponents = automaticGradient.flatMap(extendedSRGBComponents)
precondition(
    gradientComponents.map { components in
        let red = components[0]
        let green = components[1]
        let blue = components[2]
        let brightness = (red + green + blue) / 3
        return red > green && green > blue && brightness >= 0.72 && components[3] == 1
    } == true,
    "The Icon Composer document must retain its opaque, gentle warm backdrop"
)

let iconComposerArtwork = iconComposer
    .appendingPathComponent("Assets", isDirectory: true)
    .appendingPathComponent("ApplicationArtwork.png")
let referencedIconImages = (iconDocument["groups"] as? [[String: Any]] ?? []).flatMap { group in
    (group["layers"] as? [[String: Any]] ?? []).compactMap { layer in
        layer["image-name"] as? String
    }
}
precondition(
    referencedIconImages.contains(iconComposerArtwork.lastPathComponent),
    "The Icon Composer document must render Kaštan's application artwork"
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
    let colors = cornerColors(of: image)
    precondition(
        colors.count == 4 && colors.allSatisfy { color in
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            return color.redComponent > color.greenComponent
                && color.greenComponent > color.blueComponent
                && brightness >= 0.72
        },
        "\(icon.lastPathComponent) must retain its gentle warm backdrop"
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
