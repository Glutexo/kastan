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

/// Stable identifiers for the app's secondary window scenes.
enum AppWindow {
    static let information = "app-information"
    static let serviceDetail = "service-detail"
}

/// Performs native tab and window operations for the active macOS window.
@MainActor
enum AppWindowActions {
    static func newTab() {
        guard let sourceWindow = NSApplication.shared.keyWindow else { return }
        let existingWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))

        NSApplication.shared.sendAction(
            #selector(NSResponder.newWindowForTab(_:)),
            to: nil,
            from: nil
        )

        attachNewWindow(
            to: sourceWindow,
            excluding: existingWindows,
            remainingAttempts: 8
        )
    }

    static func closeTab() {
        NSApplication.shared.keyWindow?.performClose(nil)
    }

    static func closeWindow() {
        guard let window = NSApplication.shared.keyWindow else { return }

        for window in windowsToClose(for: window).reversed() {
            window.performClose(nil)
        }
    }

    /// Returns every tab hosted in the same visual window for the Close Window command.
    static func windowsToClose(for window: NSWindow) -> [NSWindow] {
        closeTargets(selected: window, tabGroup: window.tabGroup?.windows)
    }

    /// Keeps a single ungrouped window as the fallback close target.
    static func closeTargets<Element>(selected: Element, tabGroup: [Element]?) -> [Element] {
        tabGroup ?? [selected]
    }

    private static func attachNewWindow(
        to sourceWindow: NSWindow,
        excluding existingWindows: Set<ObjectIdentifier>,
        remainingAttempts: Int
    ) {
        DispatchQueue.main.async {
            let newWindow = NSApplication.shared.keyWindow.flatMap { window in
                existingWindows.contains(ObjectIdentifier(window)) ? nil : window
            } ?? NSApplication.shared.windows.first { window in
                !existingWindows.contains(ObjectIdentifier(window)) && window.canBecomeMain
            }

            if let newWindow {
                sourceWindow.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            } else if remainingAttempts > 1 {
                attachNewWindow(
                    to: sourceWindow,
                    excluding: existingWindows,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }
    }
}

/// Keeps SwiftUI's generic close commands from duplicating Kaštan's explicit tab and window actions.
@MainActor
final class ApplicationMainMenu: NSObject {
    static let shared = ApplicationMainMenu()
    private var cleanupScheduled = false

    func install() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )

        scheduleCleanup()
    }

    @objc private func menuDidAddItem(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              menu.supermenu === NSApplication.shared.mainMenu
        else { return }

        scheduleCleanup()
    }

    private func scheduleCleanup() {
        guard !cleanupScheduled else { return }
        cleanupScheduled = true

        DispatchQueue.main.async { [self] in
            cleanupScheduled = false
            for menu in NSApplication.shared.mainMenu?.items.compactMap(\.submenu) ?? [] {
                removeGenericCloseCommands(from: menu)
            }
        }
    }

    private func removeGenericCloseCommands(from menu: NSMenu) {
        let genericActions = [
            #selector(NSWindow.performClose(_:)),
            Selector(("closeAll:"))
        ]
        let genericItems = menu.items.filter { item in
            guard let action = item.action else { return false }
            return genericActions.contains(action)
        }

        for item in genericItems {
            menu.removeItem(item)
        }

        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }
    }
}

/// Gives the primary WindowGroup a complete, unambiguous set of File menu commands.
struct AppWindowCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                AppWindowActions.newTab()
            }
            .keyboardShortcut("t")

            Divider()

            Button("Close Tab") {
                AppWindowActions.closeTab()
            }
            .keyboardShortcut("w")

            Button("Close Window") {
                AppWindowActions.closeWindow()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}

/// Routes the standard About command to Kaštan's product and data-source information window.
struct AppInformationCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Kaštan") {
                openWindow(id: AppWindow.information)
            }
        }
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

            Divider()

            sectionToggle(.favoriteTimetables)

            Divider()
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
        ApplicationMainMenu.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            AppWindowCommands()
            SidebarCommands()
            AppSectionCommands()
            AppInformationCommands()
        }

        Window("About Kaštan", id: AppWindow.information) {
            AppInformationView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            AppInformationCommands()
        }

        WindowGroup("Service route", id: AppWindow.serviceDetail, for: ServiceSelection.self) { selection in
            if let selection = selection.wrappedValue {
                ServiceDetailView(selection: selection, client: client)
            }
        }
        .defaultSize(width: 760, height: 640)
        .commands {
            AppInformationCommands()
        }
    }
}
