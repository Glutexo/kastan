import AppKit
import SwiftUI

extension NSToolbar.Identifier {
    static let kastanMainWindow = NSToolbar.Identifier("cz.glutexo.kastan.main-window")
}

extension NSToolbarItem.Identifier {
    static let searchMode = NSToolbarItem.Identifier("cz.glutexo.kastan.search-mode")
    static let favoriteTimetables = NSToolbarItem.Identifier("cz.glutexo.kastan.favorite-timetables")
    static let appInformation = NSToolbarItem.Identifier("cz.glutexo.kastan.app-information")
}

/// Installs one stable AppKit toolbar instead of relying on SwiftUI's transient toolbar-item identities.
struct MainWindowToolbarInstaller: NSViewRepresentable {
    @Binding var selection: AppSection
    let openFavoriteTimetables: @MainActor () -> Void
    let openAppInformation: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selection: $selection,
            openFavoriteTimetables: openFavoriteTimetables,
            openAppInformation: openAppInformation
        )
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AttachmentView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.update(
            selection: $selection,
            openFavoriteTimetables: openFavoriteTimetables,
            openAppInformation: openAppInformation
        )
        context.coordinator.install(on: nsView.window)
    }

    static func dismantleNSView(_ nsView: AttachmentView, coordinator: Coordinator) {
        coordinator.uninstall()
        nsView.coordinator = nil
    }

    @MainActor
    final class AttachmentView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.install(on: window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        private var selection: Binding<AppSection>
        private var openFavoriteTimetables: () -> Void
        private var openAppInformation: () -> Void
        private weak var window: NSWindow?
        private weak var modeControl: NSSegmentedControl?

        lazy var toolbar: NSToolbar = {
            let toolbar = NSToolbar(identifier: .kastanMainWindow)
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.centeredItemIdentifiers = [.searchMode]
            return toolbar
        }()

        init(
            selection: Binding<AppSection>,
            openFavoriteTimetables: @escaping () -> Void,
            openAppInformation: @escaping () -> Void
        ) {
            self.selection = selection
            self.openFavoriteTimetables = openFavoriteTimetables
            self.openAppInformation = openAppInformation
            super.init()
        }

        func update(
            selection: Binding<AppSection>,
            openFavoriteTimetables: @escaping () -> Void,
            openAppInformation: @escaping () -> Void
        ) {
            self.selection = selection
            self.openFavoriteTimetables = openFavoriteTimetables
            self.openAppInformation = openAppInformation
            updateModeControlState()
            updateModeMenuState()
        }

        func install(on window: NSWindow?) {
            guard let window else { return }
            if self.window === window, window.toolbar === toolbar {
                return
            }

            uninstall()
            self.window = window
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.toolbar = toolbar
        }

        func uninstall() {
            if window?.toolbar === toolbar {
                window?.toolbar = nil
            }
            window = nil
            modeControl = nil
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace, .searchMode, .flexibleSpace, .favoriteTimetables, .appInformation]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace, .searchMode, .favoriteTimetables, .appInformation]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            switch itemIdentifier {
            case .searchMode:
                makeModeToolbarItem(retainView: flag)
            case .favoriteTimetables:
                makeActionToolbarItem(
                    identifier: itemIdentifier,
                    title: AppLocalization.string("Favorite timetables"),
                    systemImage: "star",
                    action: #selector(showFavoriteTimetables(_:))
                )
            case .appInformation:
                makeActionToolbarItem(
                    identifier: itemIdentifier,
                    title: AppLocalization.string("Show app and data source information"),
                    systemImage: "info.circle",
                    action: #selector(showAppInformation(_:))
                )
            default:
                nil
            }
        }

        private func makeModeToolbarItem(retainView: Bool) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: .searchMode)
            let label = AppLocalization.string("Search mode")
            let control = NSSegmentedControl(
                labels: AppSection.allCases.map { AppLocalization.string($0.localizationKey) },
                trackingMode: .selectOne,
                target: self,
                action: #selector(selectModeSegment(_:))
            )
            control.selectedSegment = AppSection.allCases.firstIndex(of: selection.wrappedValue) ?? 0
            control.setAccessibilityLabel(label)
            control.sizeToFit()

            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.view = control
            item.visibilityPriority = .user
            item.menuFormRepresentation = makeModeMenuRepresentation(title: label)

            if retainView {
                modeControl = control
            }
            return item
        }

        private func makeActionToolbarItem(
            identifier: NSToolbarItem.Identifier,
            title: String,
            systemImage: String,
            action: Selector
        ) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
            item.label = title
            item.paletteLabel = title
            item.toolTip = title
            item.image = image
            item.target = self
            item.action = action
            item.isBordered = true
            item.visibilityPriority = .standard

            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.image = image
            item.menuFormRepresentation = menuItem
            return item
        }

        private func makeModeMenuRepresentation(title: String) -> NSMenuItem {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            for (index, section) in AppSection.allCases.enumerated() {
                let item = NSMenuItem(
                    title: AppLocalization.string(section.localizationKey),
                    action: #selector(selectMode(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.image = NSImage(
                    systemSymbolName: section.systemImage,
                    accessibilityDescription: AppLocalization.string(section.localizationKey)
                )
                menu.addItem(item)
            }
            root.submenu = menu
            updateModeMenuState(in: menu)
            return root
        }

        private func updateModeMenuState() {
            guard let menu = toolbar.items
                .first(where: { $0.itemIdentifier == .searchMode })?
                .menuFormRepresentation?
                .submenu
            else { return }
            updateModeMenuState(in: menu)
        }

        private func updateModeMenuState(in menu: NSMenu) {
            for (index, item) in menu.items.enumerated() {
                item.state = AppSection.allCases.indices.contains(index) && AppSection.allCases[index] == selection.wrappedValue
                    ? .on
                    : .off
            }
        }

        private func updateModeControlState() {
            modeControl?.selectedSegment = AppSection.allCases.firstIndex(of: selection.wrappedValue) ?? 0
        }

        @objc private func selectMode(_ sender: NSMenuItem) {
            guard AppSection.allCases.indices.contains(sender.tag) else { return }
            selection.wrappedValue = AppSection.allCases[sender.tag]
            updateModeControlState()
            updateModeMenuState()
        }

        @objc private func selectModeSegment(_ sender: NSSegmentedControl) {
            guard AppSection.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = AppSection.allCases[sender.selectedSegment]
            updateModeMenuState()
        }

        @objc private func showFavoriteTimetables(_ sender: Any?) {
            openFavoriteTimetables()
        }

        @objc private func showAppInformation(_ sender: Any?) {
            openAppInformation()
        }
    }
}
