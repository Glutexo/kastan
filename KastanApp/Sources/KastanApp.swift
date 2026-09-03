import AppKit
import Kastan
import SwiftUI

/// Exposes the bundle icon used consistently by macOS and Kaštan's in-app identity.
@MainActor
enum ApplicationArtwork {
    static var icon: NSImage {
        NSApplication.shared.applicationIconImage ?? NSImage()
    }
}

/// Stable identifiers for the app's main and supporting window scenes.
enum AppWindow {
    static let main = "main"
    static let information = "app-information"
    static let favoriteTimetables = "favorite-timetables"
    static let connectionDetail = "connection-detail"
    static let serviceDetail = "service-detail"
}

/// Identifies one independently restorable main window while retaining its provider choice.
///
/// The unique identifier keeps two windows that use the same provider distinct when they are opened through
/// SwiftUI's value-based window API. The provider identifier remains mutable so a regular provider change can be
/// persisted as part of the scene's restoration value.
struct MainWindowSceneValue: Codable, Hashable {
    let id: UUID
    var dataSourceID: TransitDataSourceID

    init(id: UUID = UUID(), dataSourceID: TransitDataSourceID) {
        self.id = id
        self.dataSourceID = dataSourceID
    }
}

/// Remembers the provider from the main window that actually closed most recently.
@MainActor
final class LastClosedMainWindowDataSource: ObservableObject {
    static let storageKey = "lastClosedMainWindowDataSourceID"

    @Published private(set) var dataSourceID: TransitDataSourceID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dataSourceID = defaults.string(forKey: Self.storageKey).map { TransitDataSourceID($0) }
    }

    /// Records regular and explicit-only providers alike because restoration follows the last closed window exactly.
    func remember(_ dataSourceID: TransitDataSourceID) {
        guard self.dataSourceID != dataSourceID else { return }
        self.dataSourceID = dataSourceID
        defaults.set(dataSourceID.rawValue, forKey: Self.storageKey)
    }

    /// Rejects stale persisted identifiers after a provider is removed or renamed.
    func resolvedDataSourceID(in registry: TransitDataSourceRegistry) -> TransitDataSourceID {
        guard let dataSourceID, registry.dataSource(for: dataSourceID) != nil else {
            return registry.defaultDataSourceID
        }
        return dataSourceID
    }
}

/// Describes how the File menu presents provider-specific main-window creation.
struct AppWindowCommandPolicy {
    let regularDataSources: [TransitDataSourceDescriptor]
    let mockDataSource: TransitDataSourceDescriptor?
    let defaultDataSourceID: TransitDataSourceID

    init(registry: TransitDataSourceRegistry) {
        regularDataSources = registry.descriptors
        mockDataSource = registry.explicitDataSourceDescriptors.first { $0.id == .mock }
        defaultDataSourceID = registry.defaultDataSourceID
    }

    var usesProviderSubmenus: Bool {
        regularDataSources.count > 1
    }

    /// Keeps the familiar shortcuts useful without ever choosing an explicit-only provider implicitly.
    func preferredRegularDataSourceID(
        focusedDataSourceID: TransitDataSourceID?,
        lastClosedDataSourceID: TransitDataSourceID?
    ) -> TransitDataSourceID {
        let regularIDs = Set(regularDataSources.map(\.id))
        if let focusedDataSourceID, regularIDs.contains(focusedDataSourceID) {
            return focusedDataSourceID
        }
        if let lastClosedDataSourceID, regularIDs.contains(lastClosedDataSourceID) {
            return lastClosedDataSourceID
        }
        return defaultDataSourceID
    }
}

/// Distinguishes the two native destinations that share provider-selection behavior.
private enum MainWindowCreationKind {
    case window
    case tab

    var title: LocalizedStringKey {
        switch self {
        case .window: "New Window"
        case .tab: "New Tab"
        }
    }

    var mockTitle: LocalizedStringKey {
        switch self {
        case .window: "New Mock Window"
        case .tab: "New Mock Tab"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .window: "n"
        case .tab: "t"
        }
    }
}

/// Performs native tab and window operations for the active macOS window.
@MainActor
enum AppWindowActions {
    /// Creates a fresh main search window and joins it to the active window as a native tab.
    static func newTab(
        sourceWindow: NSWindow? = NSApplication.shared.keyWindow,
        openMainWindow: () -> Void
    ) {
        guard let sourceWindow else {
            openMainWindow()
            return
        }
        let existingWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))

        openMainWindow()

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
    private var mockDataSourceDisplayName: String?

    func install(mockDataSourceDisplayName: String? = nil) {
        self.mockDataSourceDisplayName = mockDataSourceDisplayName
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )

        scheduleCleanup()
    }

    @objc private func menuDidAddItem(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              Self.menu(menu, belongsTo: NSApplication.shared.mainMenu)
        else { return }

        scheduleCleanup()
    }

    /// Reapplies native alternates synchronously after SwiftUI lazily rebuilds a provider submenu.
    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              Self.menu(menu, belongsTo: NSApplication.shared.mainMenu)
        else { return }

        configureMockDataSourceAlternates(in: menu)
    }

    private func scheduleCleanup() {
        guard !cleanupScheduled else { return }
        cleanupScheduled = true

        DispatchQueue.main.async { [self] in
            cleanupScheduled = false
            for menu in NSApplication.shared.mainMenu?.items.compactMap(\.submenu) ?? [] {
                let isWindowsMenu = menu === NSApplication.shared.windowsMenu
                removeGenericCloseCommands(from: menu)
                removeRedundantAppInformationCommand(
                    from: menu,
                    isWindowsMenu: isWindowsMenu
                )
                applyFavoriteTimetablesIcon(to: menu, isWindowsMenu: isWindowsMenu)
                configureMockDataSourceAlternates(in: menu)
                removeRedundantSeparators(from: menu)
            }
        }
    }

    /// Uses AppKit's native alternate-item behavior on every supported macOS version.
    ///
    /// SwiftUI exposes modifier-key alternates only on newer systems. The command buttons are deliberately emitted
    /// beside their regular counterparts and this pass marks the mock actions as native Option alternates.
    private func configureMockDataSourceAlternates(in menu: NSMenu) {
        Self.configureMockDataSourceAlternates(
            in: menu,
            mockDataSourceDisplayName: mockDataSourceDisplayName
        )
    }

    static func configureMockDataSourceAlternates(
        in menu: NSMenu,
        mockDataSourceDisplayName: String?
    ) {
        let directTitles = [
            AppLocalization.string("New Mock Window"),
            AppLocalization.string("New Mock Tab"),
        ]

        for item in menu.items {
            if directTitles.contains(item.title) || item.title == mockDataSourceDisplayName {
                makeOptionAlternate(item)
            }

            guard let submenu = item.submenu else { continue }
            configureMockDataSourceAlternates(
                in: submenu,
                mockDataSourceDisplayName: mockDataSourceDisplayName
            )
        }
    }

    static func menu(_ menu: NSMenu, belongsTo rootMenu: NSMenu?) -> Bool {
        guard let rootMenu else { return false }
        var candidate: NSMenu? = menu
        while let current = candidate {
            if current === rootMenu { return true }
            candidate = current.supermenu
        }
        return false
    }

    private static func makeOptionAlternate(_ item: NSMenuItem) {
        item.isAlternate = true
        item.keyEquivalentModifierMask.insert(.option)
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
    }

    private func removeRedundantAppInformationCommand(from menu: NSMenu, isWindowsMenu: Bool) {
        let redundantItems = menu.items.filter { item in
            Self.isRedundantAppInformationItem(title: item.title, isWindowsMenu: isWindowsMenu)
        }

        for item in redundantItems {
            menu.removeItem(item)
        }
    }

    static func isRedundantAppInformationItem(title: String, isWindowsMenu: Bool) -> Bool {
        isWindowsMenu && title == AppLocalization.string("About Kaštan")
    }

    /// Marks the favorites-manager command like its toolbar counterpart without decorating window-list entries.
    private func applyFavoriteTimetablesIcon(to menu: NSMenu, isWindowsMenu: Bool) {
        guard isWindowsMenu else { return }

        let title = AppLocalization.string("Favorite timetables")
        guard let command = menu.items.first(where: { $0.title == title }) else { return }
        command.image = NSImage(systemSymbolName: "star", accessibilityDescription: title)
    }

    private func removeRedundantSeparators(from menu: NSMenu) {
        for index in menu.items.indices.reversed() {
            guard menu.items[index].isSeparatorItem else { continue }

            let isLeading = index == 0
            let followsSeparator = index > 0 && menu.items[index - 1].isSeparatorItem
            if isLeading || followsSeparator {
                menu.removeItem(at: index)
            }
        }

        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }
    }
}

/// Gives the primary WindowGroup a complete, unambiguous set of File menu commands.
struct AppWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activeDataSourceDescriptor) private var activeDataSourceDescriptor
    @ObservedObject private var lastClosedDataSource: LastClosedMainWindowDataSource
    private let policy: AppWindowCommandPolicy

    init(
        dataSources: TransitDataSourceRegistry,
        lastClosedDataSource: LastClosedMainWindowDataSource
    ) {
        policy = AppWindowCommandPolicy(registry: dataSources)
        _lastClosedDataSource = ObservedObject(wrappedValue: lastClosedDataSource)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            creationCommand(.window)
            creationCommand(.tab)

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

    @ViewBuilder
    private func creationCommand(_ kind: MainWindowCreationKind) -> some View {
        if policy.usesProviderSubmenus {
            Menu(kind.title) {
                providerChoices(for: kind)
            }
        } else if let dataSource = policy.regularDataSources.first {
            creationButton(kind, dataSource: dataSource, title: kind.title)
                .keyboardShortcut(kind.shortcut)

            if let mockDataSource = policy.mockDataSource {
                creationButton(kind, dataSource: mockDataSource, title: kind.mockTitle)
                    .keyboardShortcut(kind.shortcut, modifiers: [.command, .option])
            }
        }
    }

    @ViewBuilder
    private func providerChoices(for kind: MainWindowCreationKind) -> some View {
        let preferredID = policy.preferredRegularDataSourceID(
            focusedDataSourceID: activeDataSourceDescriptor?.id,
            lastClosedDataSourceID: lastClosedDataSource.dataSourceID
        )

        ForEach(policy.regularDataSources, id: \.id) { dataSource in
            if dataSource.id == preferredID {
                creationButton(
                    kind,
                    dataSource: dataSource,
                    title: LocalizedStringKey(dataSource.displayName)
                )
                .keyboardShortcut(kind.shortcut)

                if let mockDataSource = policy.mockDataSource {
                    creationButton(
                        kind,
                        dataSource: mockDataSource,
                        title: LocalizedStringKey(mockDataSource.displayName)
                    )
                    .keyboardShortcut(kind.shortcut, modifiers: [.command, .option])
                }
            } else {
                creationButton(
                    kind,
                    dataSource: dataSource,
                    title: LocalizedStringKey(dataSource.displayName)
                )
            }
        }
    }

    private func creationButton(
        _ kind: MainWindowCreationKind,
        dataSource: TransitDataSourceDescriptor,
        title: LocalizedStringKey
    ) -> some View {
        Button(title) {
            let sceneValue = MainWindowSceneValue(dataSourceID: dataSource.id)
            switch kind {
            case .window:
                openWindow(id: AppWindow.main, value: sceneValue)
            case .tab:
                AppWindowActions.newTab {
                    openWindow(id: AppWindow.main, value: sceneValue)
                }
            }
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

/// Exposes the same maintained external destinations as Kaštan's information window.
struct AppHelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            ForEach(AppInformationLinks.localized.destinations) { destination in
                Button {
                    NSWorkspace.shared.open(destination.url)
                } label: {
                    Label(
                        LocalizedStringKey(destination.titleKey),
                        systemImage: destination.systemImage
                    )
                }
            }
        }
    }
}

/// Defines the current-value shortcuts grouped inside the Edit menu.
enum FillCurrentAction: CaseIterable, Hashable, Identifiable {
    case fromPlace
    case toPlace
    case dateAndTime
    case date
    case time

    static let placeActions: [Self] = [.fromPlace, .toPlace]
    static let temporalActions: [Self] = [.dateAndTime, .date, .time]

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .fromPlace:
            "From Place"
        case .toPlace:
            "To Place"
        case .dateAndTime:
            "Date and time"
        case .date:
            "Date"
        case .time:
            "Time"
        }
    }

    var systemImage: String {
        switch self {
        case .fromPlace, .toPlace:
            "location"
        case .dateAndTime:
            "calendar.badge.clock"
        case .date:
            "calendar"
        case .time:
            "clock"
        }
    }

    /// Keeps unsupported values visible but disabled as the active search mode changes.
    static func supportedActions(for section: AppSection) -> Set<Self> {
        switch section {
        case .connections:
            Set(allCases)
        case .departures:
            Set(temporalActions)
        case .stationTimetables:
            [.date]
        }
    }
}

/// Connects Edit-menu search commands to the editable form in the focused main window.
struct SearchEditCommandContext {
    let enabledFillCurrentActions: Set<FillCurrentAction>
    let performFillCurrent: (FillCurrentAction) -> Void
    let swapPlaces: (() -> Void)?

    func isFillCurrentEnabled(_ action: FillCurrentAction) -> Bool {
        enabledFillCurrentActions.contains(action)
    }
}

struct SearchEditCommandContextKey: FocusedValueKey {
    typealias Value = SearchEditCommandContext
}

extension FocusedValues {
    var searchEditCommandContext: SearchEditCommandContext? {
        get { self[SearchEditCommandContextKey.self] }
        set { self[SearchEditCommandContextKey.self] = newValue }
    }
}

/// Keeps current-value and route-swap actions together in the standard Edit menu.
struct SearchEditCommands: Commands {
    @FocusedValue(\.searchEditCommandContext) private var context

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Menu("Fill Current") {
                ForEach(FillCurrentAction.placeActions) { action in
                    fillCurrentButton(action)
                }

                Divider()

                ForEach(FillCurrentAction.temporalActions) { action in
                    fillCurrentButton(action)
                }
            }

            Button {
                context?.swapPlaces?()
            } label: {
                Label("Swap From and To", systemImage: "arrow.left.arrow.right")
            }
            .disabled(context?.swapPlaces == nil)

            Divider()
        }
    }

    private func fillCurrentButton(_ action: FillCurrentAction) -> some View {
        Button {
            context?.performFillCurrent(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .disabled(context?.isFillCurrentEnabled(action) != true)
    }
}

/// Defines the result-detail actions shared by the active window's toolbar and the File menu.
enum ResultDetailAction: CaseIterable, Hashable, Identifiable {
    case sendByEmail
    case addToCalendar
    case openPDF
    case share

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .sendByEmail:
            ConnectionEmailAction.sendViaIDOS.title
        case .addToCalendar:
            "Add to Calendar"
        case .openPDF:
            PDFExportAction.openInPreview.title
        case .share:
            ResultSharingAction.link.title
        }
    }

    var systemImage: String {
        switch self {
        case .sendByEmail:
            ConnectionEmailAction.sendViaIDOS.systemImage
        case .addToCalendar:
            "calendar.badge.plus"
        case .openPDF:
            PDFExportAction.openInPreview.systemImage
        case .share:
            ResultSharingAction.link.systemImage
        }
    }

    /// Replaces result-action presentations when their Option alternates are active.
    func title(
        emailAction: ConnectionEmailAction = .sendViaIDOS,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview,
        sharingAction: ResultSharingAction = .link
    ) -> LocalizedStringKey {
        switch self {
        case .sendByEmail:
            emailAction.title
        case .addToCalendar:
            calendarExportAction.title
        case .openPDF:
            pdfExportAction.title
        case .share:
            sharingAction.title
        }
    }

    func systemImage(
        emailAction: ConnectionEmailAction = .sendViaIDOS,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview,
        sharingAction: ResultSharingAction = .link
    ) -> String {
        switch self {
        case .sendByEmail:
            emailAction.systemImage
        case .addToCalendar:
            calendarExportAction.systemImage
        case .openPDF:
            pdfExportAction.systemImage
        case .share:
            sharingAction.systemImage
        }
    }

    /// Keeps email connection-specific while every loaded result retains portable text sharing.
    static func availableActions(
        canSendByEmail: Bool,
        canAddToCalendar: Bool = true,
        canOpenPDF: Bool = true
    ) -> [Self] {
        allCases.filter { action in
            switch action {
            case .sendByEmail:
                canSendByEmail
            case .addToCalendar:
                canAddToCalendar
            case .openPDF:
                canOpenPDF
            case .share:
                true
            }
        }
    }
}

/// Maps a provider's advertised export contract to result controls that can safely be presented.
struct ResultDetailActionAvailability: Equatable {
    let canSendByEmail: Bool
    let canAddToCalendar: Bool
    let canOpenPDF: Bool

    /// Mail composition needs an email draft and at least one attachment format advertised by the provider.
    var canComposeConnectionEmailInMail: Bool {
        canSendByEmail && (canAddToCalendar || canOpenPDF)
    }

    static func connection(_ descriptor: TransitDataSourceDescriptor) -> Self {
        Self(
            canSendByEmail: descriptor.supports(.connectionEmail),
            canAddToCalendar: descriptor.supports(.connectionCalendarExport),
            canOpenPDF: descriptor.supports(.connectionPDFExport)
        )
    }

    static func service(_ descriptor: TransitDataSourceDescriptor) -> Self {
        Self(
            canSendByEmail: false,
            canAddToCalendar: descriptor.supports(.serviceCalendarExport),
            canOpenPDF: descriptor.supports(.servicePDFExport)
        )
    }
}

/// Connects commands in the macOS main menu to the currently focused connection or service detail.
struct ResultDetailCommandContext {
    let hasLoadedResult: Bool
    let isPerformingAction: Bool
    let permanentLink: URL?
    let shareText: String?
    let availability: ResultDetailActionAvailability
    let performEmailAction: ((ConnectionEmailAction) -> Void)?
    let performCalendarAction: (CalendarExportAction) -> Void
    let performPDFAction: (PDFExportAction) -> Void

    init(
        hasLoadedResult: Bool,
        isPerformingAction: Bool,
        permanentLink: URL?,
        shareText: String?,
        availability: ResultDetailActionAvailability = .init(
            canSendByEmail: true,
            canAddToCalendar: true,
            canOpenPDF: true
        ),
        performEmailAction: ((ConnectionEmailAction) -> Void)? = nil,
        performCalendarAction: @escaping (CalendarExportAction) -> Void,
        performPDFAction: @escaping (PDFExportAction) -> Void
    ) {
        self.hasLoadedResult = hasLoadedResult
        self.isPerformingAction = isPerformingAction
        self.permanentLink = permanentLink
        self.shareText = shareText
        self.availability = availability
        self.performEmailAction = performEmailAction
        self.performCalendarAction = performCalendarAction
        self.performPDFAction = performPDFAction
    }

    func isEnabled(_ action: ResultDetailAction) -> Bool {
        guard !isPerformingAction else { return false }

        switch action {
        case .sendByEmail:
            return availability.canSendByEmail && hasLoadedResult && performEmailAction != nil
        case .addToCalendar:
            return availability.canAddToCalendar && hasLoadedResult
        case .openPDF:
            return availability.canOpenPDF && hasLoadedResult
        case .share:
            return hasLoadedResult && (permanentLink != nil || shareText?.isEmpty == false)
        }
    }
}

struct ResultDetailCommandContextKey: FocusedValueKey {
    typealias Value = ResultDetailCommandContext
}

extension FocusedValues {
    var resultDetailCommandContext: ResultDetailCommandContext? {
        get { self[ResultDetailCommandContextKey.self] }
        set { self[ResultDetailCommandContextKey.self] = newValue }
    }
}

/// Mirrors every result-detail toolbar action in the application's single File menu command group.
struct ResultDetailCommands: Commands {
    @FocusedValue(\.resultDetailCommandContext) private var context

    var body: some Commands {
        CommandGroup(after: .importExport) {
            if context?.availability.canSendByEmail != false {
                ConnectionEmailButton(
                    placement: .menu,
                    canComposeInMail: context?.availability.canComposeConnectionEmailInMail != false
                ) { emailAction in
                    context?.performEmailAction?(emailAction)
                } label: { emailAction in
                    actionLabel(.sendByEmail, emailAction: emailAction)
                }
                .disabled(context?.isEnabled(.sendByEmail) != true)
            }
            if context?.availability.canAddToCalendar != false {
                CalendarExportButton(placement: .menu) { calendarExportAction in
                    context?.performCalendarAction(calendarExportAction)
                } label: { calendarExportAction in
                    actionLabel(.addToCalendar, calendarExportAction: calendarExportAction)
                }
                .disabled(context?.isEnabled(.addToCalendar) != true)
            }
            if context?.availability.canOpenPDF != false {
                PDFExportButton(placement: .menu) { pdfExportAction in
                    context?.performPDFAction(pdfExportAction)
                } label: { pdfExportAction in
                    actionLabel(.openPDF, pdfExportAction: pdfExportAction)
                }
                .disabled(context?.isEnabled(.openPDF) != true)
            }

            ResultShareButton(
                link: context?.permanentLink,
                text: context?.shareText,
                placement: .menu
            ) { sharingAction in
                actionLabel(.share, sharingAction: sharingAction)
            }
            .disabled(context?.isEnabled(.share) != true)
        }
    }

    private func actionLabel(
        _ action: ResultDetailAction,
        emailAction: ConnectionEmailAction = .sendViaIDOS,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview,
        sharingAction: ResultSharingAction = .link
    ) -> some View {
        Label(
            action.title(
                emailAction: emailAction,
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction,
                sharingAction: sharingAction
            ),
            systemImage: action.systemImage(
                emailAction: emailAction,
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction,
                sharingAction: sharingAction
            )
        )
    }
}

/// Keeps search navigation and application-wide result presentation in the standard View menu.
struct AppSectionCommands: Commands {
    @FocusedValue(\.appSectionSelection) private var selection: Binding<AppSection>?
    @FocusedValue(\.availableAppSections) private var availableSections: Set<AppSection>?
    @FocusedValue(\.activeDataSourceDescriptor) private var activeDataSourceDescriptor
    @Binding var showsConnectionBadges: Bool
    @Binding var showsItemDetails: Bool
    @Binding var showsAlternatingRowBackgrounds: Bool
    @Binding var showsSymbolsAsText: Bool
    @Binding var showsAddressSuggestions: Bool
    @Binding var showsBoroughSuggestions: Bool
    @Binding var showsMunicipalitySuggestions: Bool

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            sectionToggle(.connections)
            sectionToggle(.departures)
            sectionToggle(.stationTimetables)

            Divider()

            Toggle(isOn: $showsConnectionBadges) {
                Label("Show connection badges", systemImage: "tag")
            }
            Toggle(isOn: $showsItemDetails) {
                Label("Show item details", systemImage: "info.circle")
            }
            Toggle(isOn: $showsAlternatingRowBackgrounds) {
                Label(
                    "Show alternating row backgrounds",
                    systemImage: AlternatingRowBackgroundPresentation.menuSystemImage
                )
            }
            Toggle(isOn: $showsSymbolsAsText) {
                Label("Replace symbols with text", systemImage: "textformat")
            }

            Divider()

            if activeDataSourceDescriptor?.supports(.placeSuggestions) != false {
                Menu {
                    Toggle("Addresses", isOn: $showsAddressSuggestions)
                    Toggle("Boroughs", isOn: $showsBoroughSuggestions)
                    Toggle("Municipalities", isOn: $showsMunicipalitySuggestions)
                } label: {
                    Label("Place suggestions", systemImage: "text.magnifyingglass")
                }

                Divider()
            }
        }
    }

    private func sectionToggle(_ section: AppSection) -> some View {
        Toggle(isOn: binding(for: section)) {
            Label(section.title, systemImage: section.systemImage)
        }
        .disabled(selection == nil || availableSections?.contains(section) != true)
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
    /// Preserves the established search baseline while fitting every complete localized journey-option row.
    static let baselineMainWindowWidth: CGFloat = 522
    static let minimumMainWindowWidth = max(
        baselineMainWindowWidth,
        DetailLayout.minimumAvailableWidth(
            fittingContentWidth: JourneyOptionRowLayout.minimumContentWidth
        )
    )
    /// Opens new main windows directly at the narrowest width supported by the active localization.
    static let defaultMainWindowWidth = minimumMainWindowWidth

    @AppStorage(ConnectionBadgePreference.storageKey)
    private var showsConnectionBadges = ConnectionBadgePreference.defaultValue
    @AppStorage(ResultItemDetailsPreference.storageKey)
    private var showsItemDetails = ResultItemDetailsPreference.defaultValue
    @AppStorage(AlternatingRowBackgroundPreference.storageKey)
    private var showsAlternatingRowBackgrounds = AlternatingRowBackgroundPreference.defaultValue
    @AppStorage(SymbolTextPreference.storageKey)
    private var showsSymbolsAsText = SymbolTextPreference.defaultValue
    @AppStorage(PlaceSuggestionVisibilityPreference.addressesStorageKey)
    private var showsAddressSuggestions = PlaceSuggestionVisibilityPreference.defaultValue
    @AppStorage(PlaceSuggestionVisibilityPreference.boroughsStorageKey)
    private var showsBoroughSuggestions = PlaceSuggestionVisibilityPreference.defaultValue
    @AppStorage(PlaceSuggestionVisibilityPreference.municipalitiesStorageKey)
    private var showsMunicipalitySuggestions = PlaceSuggestionVisibilityPreference.defaultValue
    /// Registers concrete providers once and routes restorable results back to the source that issued them.
    private let dataSources = TransitDataSourceRegistry.builtIn
    @StateObject private var lastClosedDataSource = LastClosedMainWindowDataSource()

    init() {
        SymbolTextPreference.migrateLegacyValues()
        ApplicationMainMenu.shared.install(
            mockDataSourceDisplayName: dataSources.explicitDataSourceDescriptors
                .first { $0.id == .mock }?
                .displayName
        )
    }

    var body: some Scene {
        WindowGroup(id: AppWindow.main, for: MainWindowSceneValue.self) { sceneValue in
            ContentView(
                sceneValue: sceneValue,
                dataSources: dataSources,
                lastClosedDataSource: lastClosedDataSource,
                showsConnectionBadges: showsConnectionBadges,
                showsItemDetails: showsItemDetails,
                showsServiceInformationText: showsSymbolsAsText,
                showsStopNoteText: showsSymbolsAsText
            )
                .environment(\.showsAlternatingRowBackgrounds, showsAlternatingRowBackgrounds)
                .environment(
                    \.placeSuggestionVisibility,
                    PlaceSuggestionVisibility(
                        showsAddresses: showsAddressSuggestions,
                        showsBoroughs: showsBoroughSuggestions,
                        showsMunicipalities: showsMunicipalitySuggestions
                    )
                )
                .frame(minWidth: Self.minimumMainWindowWidth, minHeight: 520)
        } defaultValue: {
            MainWindowSceneValue(
                dataSourceID: lastClosedDataSource.resolvedDataSourceID(in: dataSources)
            )
        }
        .defaultSize(width: Self.defaultMainWindowWidth, height: 720)
        .commands {
            AppWindowCommands(
                dataSources: dataSources,
                lastClosedDataSource: lastClosedDataSource
            )
            ResultDetailCommands()
            AppSectionCommands(
                showsConnectionBadges: $showsConnectionBadges,
                showsItemDetails: $showsItemDetails,
                showsAlternatingRowBackgrounds: $showsAlternatingRowBackgrounds,
                showsSymbolsAsText: $showsSymbolsAsText,
                showsAddressSuggestions: $showsAddressSuggestions,
                showsBoroughSuggestions: $showsBoroughSuggestions,
                showsMunicipalitySuggestions: $showsMunicipalitySuggestions
            )
            SearchEditCommands()
            AppInformationCommands()
            AppHelpCommands()
        }

        Window("Favorite timetables", id: AppWindow.favoriteTimetables) {
            NavigationStack {
                FavoriteTimetablesView(
                    timetables: dataSources.descriptors.flatMap { descriptor in
                        dataSources.dataSource(for: descriptor.id)?.timetables ?? []
                    },
                    dataSourceDescriptors: dataSources.descriptors
                )
            }
            .frame(minWidth: FavoriteTimetablesView.minimumWindowWidth, minHeight: 520)
        }
        .defaultSize(width: FavoriteTimetablesView.defaultWindowWidth, height: 620)
        .defaultPosition(.center)

        Window("About Kaštan", id: AppWindow.information) {
            AppInformationView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        WindowGroup("Service route", id: AppWindow.serviceDetail, for: ServiceSelection.self) { selection in
            if let selection = selection.wrappedValue,
               let dataSource = dataSources.dataSource(for: selection.timetable.dataSourceID) {
                ServiceDetailWindowContent(
                    selection: selection,
                    client: dataSource,
                    showsItemDetails: showsItemDetails,
                    showsStopNoteText: showsSymbolsAsText
                )
                .environment(\.showsAlternatingRowBackgrounds, showsAlternatingRowBackgrounds)
            }
        }
        .commandsRemoved()
        .defaultSize(width: ServiceDetailView.defaultWindowWidth, height: 640)

        WindowGroup("Connection detail", id: AppWindow.connectionDetail, for: ConnectionSelection.self) { selection in
            if let selection = selection.wrappedValue,
               let dataSource = dataSources.dataSource(for: selection.dataSourceID) {
                ConnectionDetailWindowContent(
                    selection: selection,
                    client: dataSource,
                    showsConnectionBadges: showsConnectionBadges,
                    showsItemDetails: showsItemDetails,
                    showsServiceInformationText: showsSymbolsAsText,
                    showsStopNoteText: showsSymbolsAsText
                )
                .environment(\.showsAlternatingRowBackgrounds, showsAlternatingRowBackgrounds)
            }
        }
        .commandsRemoved()
        .defaultSize(width: ConnectionDetailView.defaultWindowWidth, height: 640)
    }
}
