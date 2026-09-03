import AppKit
import Kastan
import SwiftUI

extension NSToolbar.Identifier {
    static let kastanMainWindow = NSToolbar.Identifier("cz.glutexo.kastan.main-window")
}

extension NSToolbarItem.Identifier {
    static let dataSource = NSToolbarItem.Identifier("cz.glutexo.kastan.data-source")
    static let searchMode = NSToolbarItem.Identifier("cz.glutexo.kastan.search-mode")
    static let favoriteTimetables = NSToolbarItem.Identifier("cz.glutexo.kastan.favorite-timetables")
    static let appInformation = NSToolbarItem.Identifier("cz.glutexo.kastan.app-information")
}

/// Keeps restored main windows inside the width supported by every editable search form.
@MainActor
enum MainWindowWidthPresentation {
    static func apply(to window: NSWindow, minimumContentWidth: CGFloat) {
        window.contentMinSize.width = max(window.contentMinSize.width, minimumContentWidth)

        let contentSize = window.contentRect(forFrameRect: window.frame).size
        guard contentSize.width < minimumContentWidth else { return }

        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: minimumContentWidth, height: contentSize.height))
        window.setFrameTopLeftPoint(topLeft)
    }
}

/// Installs one stable AppKit toolbar instead of relying on SwiftUI's transient toolbar-item identities.
struct MainWindowToolbarInstaller: NSViewRepresentable {
    @Binding var selection: AppSection
    @Binding var dataSourceSelection: TransitDataSourceID
    let sections: [AppSection]
    let dataSourceDescriptors: [TransitDataSourceDescriptor]
    let allowsDataSourceSelection: Bool
    let openFavoriteTimetables: @MainActor () -> Void
    let openAppInformation: @MainActor () -> Void

    init(
        selection: Binding<AppSection>,
        sections: [AppSection] = AppSection.allCases,
        dataSourceSelection: Binding<TransitDataSourceID> = .constant(.idos),
        dataSourceDescriptors: [TransitDataSourceDescriptor] = [.idos],
        allowsDataSourceSelection: Bool = true,
        openFavoriteTimetables: @escaping @MainActor () -> Void,
        openAppInformation: @escaping @MainActor () -> Void
    ) {
        _selection = selection
        _dataSourceSelection = dataSourceSelection
        self.sections = sections
        self.dataSourceDescriptors = dataSourceDescriptors
        self.allowsDataSourceSelection = allowsDataSourceSelection
        self.openFavoriteTimetables = openFavoriteTimetables
        self.openAppInformation = openAppInformation
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selection: $selection,
            sections: sections,
            dataSourceSelection: $dataSourceSelection,
            dataSourceDescriptors: dataSourceDescriptors,
            allowsDataSourceSelection: allowsDataSourceSelection,
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
            sections: sections,
            dataSourceSelection: $dataSourceSelection,
            dataSourceDescriptors: dataSourceDescriptors,
            allowsDataSourceSelection: allowsDataSourceSelection,
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
        private var sections: [AppSection]
        private var dataSourceSelection: Binding<TransitDataSourceID>
        private var dataSourceDescriptors: [TransitDataSourceDescriptor]
        private var allowsDataSourceSelection: Bool
        private var openFavoriteTimetables: () -> Void
        private var openAppInformation: () -> Void
        private weak var window: NSWindow?
        private weak var modeControl: NSSegmentedControl?
        private weak var dataSourceControl: NSPopUpButton?

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
            sections: [AppSection] = AppSection.allCases,
            dataSourceSelection: Binding<TransitDataSourceID> = .constant(.idos),
            dataSourceDescriptors: [TransitDataSourceDescriptor] = [.idos],
            allowsDataSourceSelection: Bool = true,
            openFavoriteTimetables: @escaping () -> Void,
            openAppInformation: @escaping () -> Void
        ) {
            self.selection = selection
            self.sections = sections
            self.dataSourceSelection = dataSourceSelection
            self.dataSourceDescriptors = dataSourceDescriptors
            self.allowsDataSourceSelection = allowsDataSourceSelection
            self.openFavoriteTimetables = openFavoriteTimetables
            self.openAppInformation = openAppInformation
            super.init()
        }

        func update(
            selection: Binding<AppSection>,
            sections: [AppSection],
            dataSourceSelection: Binding<TransitDataSourceID>,
            dataSourceDescriptors: [TransitDataSourceDescriptor],
            allowsDataSourceSelection: Bool = true,
            openFavoriteTimetables: @escaping () -> Void,
            openAppInformation: @escaping () -> Void
        ) {
            let sectionsChanged = self.sections != sections
            let descriptorsChanged = self.dataSourceDescriptors != dataSourceDescriptors
            let availabilityChanged = self.allowsDataSourceSelection != allowsDataSourceSelection
            self.selection = selection
            self.sections = sections
            self.dataSourceSelection = dataSourceSelection
            self.dataSourceDescriptors = dataSourceDescriptors
            self.allowsDataSourceSelection = allowsDataSourceSelection
            self.openFavoriteTimetables = openFavoriteTimetables
            self.openAppInformation = openAppInformation
            if sectionsChanged {
                refreshModeItem()
            }
            if descriptorsChanged || availabilityChanged {
                refreshDataSourceItem()
            }
            updateModeControlState()
            updateModeMenuState()
            updateDataSourceControlState()
            updateDataSourceMenuState()
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
            MainWindowWidthPresentation.apply(
                to: window,
                minimumContentWidth: KastanApp.minimumMainWindowWidth
            )
        }

        func uninstall() {
            if window?.toolbar === toolbar {
                window?.toolbar = nil
            }
            window = nil
            modeControl = nil
            dataSourceControl = nil
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers: [NSToolbarItem.Identifier] = []
            if showsDataSourceSelector {
                identifiers.append(.dataSource)
            }
            identifiers += [.flexibleSpace, .searchMode, .flexibleSpace, .favoriteTimetables, .appInformation]
            return identifiers
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            var identifiers: [NSToolbarItem.Identifier] = [.flexibleSpace, .searchMode]
            if showsDataSourceSelector {
                identifiers.append(.dataSource)
            }
            identifiers += [.favoriteTimetables, .appInformation]
            return identifiers
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            switch itemIdentifier {
            case .dataSource:
                showsDataSourceSelector ? makeDataSourceToolbarItem(retainView: flag) : nil
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
                    title: AppLocalization.string("App and data source information"),
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
                labels: sections.map { AppLocalization.string($0.localizationKey) },
                trackingMode: .selectOne,
                target: self,
                action: #selector(selectModeSegment(_:))
            )
            control.selectedSegment = sections.firstIndex(of: selection.wrappedValue) ?? 0
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

        /// Presents registered providers only when choosing one can change the active window.
        private func makeDataSourceToolbarItem(retainView: Bool) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: .dataSource)
            let label = AppLocalization.string("Data source")
            let control = NSPopUpButton(frame: .zero, pullsDown: false)
            control.controlSize = .regular
            control.target = self
            control.action = #selector(selectDataSource(_:))
            for descriptor in dataSourceDescriptors {
                control.addItem(withTitle: descriptor.displayName)
                control.lastItem?.representedObject = descriptor.id.rawValue
            }
            control.setAccessibilityLabel(label)
            control.sizeToFit()

            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.view = control
            item.visibilityPriority = .user
            item.menuFormRepresentation = makeDataSourceMenuRepresentation(title: label)

            if retainView {
                dataSourceControl = control
            }
            updateDataSourceControlState(in: control)
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
            for (index, section) in sections.enumerated() {
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

        private func makeDataSourceMenuRepresentation(title: String) -> NSMenuItem {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            for (index, descriptor) in dataSourceDescriptors.enumerated() {
                let item = NSMenuItem(
                    title: descriptor.displayName,
                    action: #selector(selectDataSourceMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            root.submenu = menu
            updateDataSourceMenuState(in: menu)
            return root
        }

        private var showsDataSourceSelector: Bool {
            allowsDataSourceSelection && dataSourceDescriptors.count > 1
        }

        /// Rebuilds the segmented control when a newly selected provider advertises other modes.
        private func refreshModeItem() {
            guard let item = toolbar.items.first(where: { $0.itemIdentifier == .searchMode }) else {
                return
            }
            let replacement = makeModeToolbarItem(retainView: true)
            item.view = replacement.view
            item.menuFormRepresentation = replacement.menuFormRepresentation
        }

        private func refreshDataSourceItem() {
            guard let item = toolbar.items.first(where: { $0.itemIdentifier == .dataSource }) else {
                return
            }
            let replacement = makeDataSourceToolbarItem(retainView: true)
            item.view = replacement.view
            item.menuFormRepresentation = replacement.menuFormRepresentation
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
                item.state = sections.indices.contains(index) && sections[index] == selection.wrappedValue
                    ? .on
                    : .off
            }
        }

        private func updateModeControlState() {
            modeControl?.selectedSegment = sections.firstIndex(of: selection.wrappedValue) ?? 0
        }

        private func updateDataSourceControlState() {
            guard let dataSourceControl else { return }
            updateDataSourceControlState(in: dataSourceControl)
        }

        private func updateDataSourceControlState(in control: NSPopUpButton) {
            let selectedIndex = dataSourceDescriptors.firstIndex {
                $0.id == dataSourceSelection.wrappedValue
            } ?? 0
            control.selectItem(at: selectedIndex)
        }

        private func updateDataSourceMenuState() {
            guard let menu = toolbar.items
                .first(where: { $0.itemIdentifier == .dataSource })?
                .menuFormRepresentation?
                .submenu
            else { return }
            updateDataSourceMenuState(in: menu)
        }

        private func updateDataSourceMenuState(in menu: NSMenu) {
            for (index, item) in menu.items.enumerated() {
                item.state = dataSourceDescriptors.indices.contains(index) &&
                    dataSourceDescriptors[index].id == dataSourceSelection.wrappedValue
                    ? .on
                    : .off
            }
        }

        @objc private func selectMode(_ sender: NSMenuItem) {
            guard sections.indices.contains(sender.tag) else { return }
            selection.wrappedValue = sections[sender.tag]
            updateModeControlState()
            updateModeMenuState()
        }

        @objc private func selectModeSegment(_ sender: NSSegmentedControl) {
            guard sections.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = sections[sender.selectedSegment]
            updateModeMenuState()
        }

        @objc private func selectDataSource(_ sender: NSPopUpButton) {
            guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
            dataSourceSelection.wrappedValue = TransitDataSourceID(rawValue)
            updateDataSourceMenuState()
        }

        @objc private func selectDataSourceMenuItem(_ sender: NSMenuItem) {
            guard dataSourceDescriptors.indices.contains(sender.tag) else { return }
            dataSourceSelection.wrappedValue = dataSourceDescriptors[sender.tag].id
            updateDataSourceControlState()
            updateDataSourceMenuState()
        }

        @objc private func showFavoriteTimetables(_ sender: Any?) {
            openFavoriteTimetables()
        }

        @objc private func showAppInformation(_ sender: Any?) {
            openAppInformation()
        }
    }
}
