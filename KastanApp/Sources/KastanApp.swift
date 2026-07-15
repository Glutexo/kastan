import AppKit
import Kastan
import SwiftUI

/// Keeps Kaštan's compiled artwork consistent between the Dock and in-app identity elements.
@MainActor
enum ApplicationArtwork {
    static let icon: NSImage = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url)
        else {
            return NSApplication.shared.applicationIconImage ?? NSImage()
        }
        return image
    }()

    static func installAsSystemIcon() {
        NSApplication.shared.applicationIconImage = icon
    }
}

/// Launches the native Kaštan experience while sharing all IDOS behavior with the CLI and MCP server.
@main
struct KastanApp: App {
    private let client = IDOSClient()

    init() {
        ApplicationArtwork.installAsSystemIcon()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            SidebarCommands()
        }
    }
}
