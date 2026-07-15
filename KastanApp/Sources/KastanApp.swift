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

/// Mirrors the active window's primary navigation in the standard View menu.
struct AppSectionCommands: Commands {
    @FocusedValue(\.appSectionSelection) private var selection: Binding<AppSection>?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            sectionToggle(.connections)
            sectionToggle(.departures)
        }
    }

    private func sectionToggle(_ section: AppSection) -> some View {
        Toggle(isOn: binding(for: section)) {
            Label(section.title, systemImage: section.systemImage)
        }
        .disabled(selection == nil)
    }

    private func binding(for section: AppSection) -> Binding<Bool> {
        Binding(
            get: { selection?.wrappedValue == section },
            set: { isSelected in
                if isSelected {
                    selection?.wrappedValue = section
                }
            }
        )
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
            AppSectionCommands()
        }
    }
}
