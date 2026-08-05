import AppKit
import Kastan
import SwiftUI

/// Keeps Kaštan's transparent artwork consistent between the Dock and in-app identity elements.
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

    /// Bypasses macOS's legacy-icon frame while retaining the original freeform chestnut in the Dock.
    static func installAsDockIcon() {
        let imageView = NSImageView(
            frame: NSRect(origin: .zero, size: NSSize(width: 128, height: 128))
        )
        imageView.image = icon
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown

        NSApplication.shared.dockTile.contentView = imageView
        NSApplication.shared.dockTile.display()
    }
}

/// Stable identifiers for the app's secondary window scenes.
enum AppWindow {
    static let information = "app-information"
    static let favoriteTimetables = "favorite-timetables"
    static let connectionDetail = "connection-detail"
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
                let isWindowsMenu = menu === NSApplication.shared.windowsMenu
                removeGenericCloseCommands(from: menu)
                removeRedundantAppInformationCommand(
                    from: menu,
                    isWindowsMenu: isWindowsMenu
                )
                applyFavoriteTimetablesIcon(to: menu, isWindowsMenu: isWindowsMenu)
                removeRedundantSeparators(from: menu)
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
        hasPermanentLink: Bool,
        canSendByEmail: Bool
    ) -> [Self] {
        allCases.filter { action in
            switch action {
            case .addToCalendar, .openPDF, .share:
                true
            case .sendByEmail:
                hasPermanentLink && canSendByEmail
            }
        }
    }
}

/// Connects commands in the macOS main menu to the currently focused connection or service detail.
struct ResultDetailCommandContext {
    let hasLoadedResult: Bool
    let isPerformingAction: Bool
    let permanentLink: URL?
    let shareText: String?
    let performEmailAction: ((ConnectionEmailAction) -> Void)?
    let performCalendarAction: (CalendarExportAction) -> Void
    let performPDFAction: (PDFExportAction) -> Void

    init(
        hasLoadedResult: Bool,
        isPerformingAction: Bool,
        permanentLink: URL?,
        shareText: String?,
        performEmailAction: ((ConnectionEmailAction) -> Void)? = nil,
        performCalendarAction: @escaping (CalendarExportAction) -> Void,
        performPDFAction: @escaping (PDFExportAction) -> Void
    ) {
        self.hasLoadedResult = hasLoadedResult
        self.isPerformingAction = isPerformingAction
        self.permanentLink = permanentLink
        self.shareText = shareText
        self.performEmailAction = performEmailAction
        self.performCalendarAction = performCalendarAction
        self.performPDFAction = performPDFAction
    }

    func isEnabled(_ action: ResultDetailAction) -> Bool {
        guard !isPerformingAction else { return false }

        switch action {
        case .addToCalendar, .openPDF:
            return hasLoadedResult
        case .sendByEmail:
            return hasLoadedResult && permanentLink != nil && performEmailAction != nil
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
            ConnectionEmailButton(placement: .menu) { emailAction in
                context?.performEmailAction?(emailAction)
            } label: { emailAction in
                actionLabel(.sendByEmail, emailAction: emailAction)
            }
            .disabled(context?.isEnabled(.sendByEmail) != true)
            CalendarExportButton(placement: .menu) { calendarExportAction in
                context?.performCalendarAction(calendarExportAction)
            } label: { calendarExportAction in
                actionLabel(.addToCalendar, calendarExportAction: calendarExportAction)
            }
            .disabled(context?.isEnabled(.addToCalendar) != true)
            PDFExportButton(placement: .menu) { pdfExportAction in
                context?.performPDFAction(pdfExportAction)
            } label: { pdfExportAction in
                actionLabel(.openPDF, pdfExportAction: pdfExportAction)
            }
            .disabled(context?.isEnabled(.openPDF) != true)

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
    @Binding var showsConnectionBadges: Bool
    @Binding var showsItemDetails: Bool
    @Binding var showsAlternatingRowBackgrounds: Bool
    @Binding var showsSymbolsAsText: Bool

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
    /// Retains usable compact search forms and toolbar actions at the narrowest supported main-window size.
    static let minimumMainWindowWidth: CGFloat = 522
    /// Opens new main windows directly in the fully supported compact layout.
    static let defaultMainWindowWidth = minimumMainWindowWidth

    @AppStorage(ConnectionBadgePreference.storageKey)
    private var showsConnectionBadges = ConnectionBadgePreference.defaultValue
    @AppStorage(ResultItemDetailsPreference.storageKey)
    private var showsItemDetails = ResultItemDetailsPreference.defaultValue
    @AppStorage(AlternatingRowBackgroundPreference.storageKey)
    private var showsAlternatingRowBackgrounds = AlternatingRowBackgroundPreference.defaultValue
    @AppStorage(SymbolTextPreference.storageKey)
    private var showsSymbolsAsText = SymbolTextPreference.defaultValue
    private let client = IDOSClient()

    init() {
        SymbolTextPreference.migrateLegacyValues()
        ApplicationArtwork.installAsDockIcon()
        ApplicationMainMenu.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                client: client,
                showsConnectionBadges: showsConnectionBadges,
                showsItemDetails: showsItemDetails,
                showsServiceInformationText: showsSymbolsAsText,
                showsStopNoteText: showsSymbolsAsText
            )
                .environment(\.showsAlternatingRowBackgrounds, showsAlternatingRowBackgrounds)
                .frame(minWidth: Self.minimumMainWindowWidth, minHeight: 520)
        }
        .defaultSize(width: Self.defaultMainWindowWidth, height: 720)
        .commands {
            AppWindowCommands()
            ResultDetailCommands()
            AppSectionCommands(
                showsConnectionBadges: $showsConnectionBadges,
                showsItemDetails: $showsItemDetails,
                showsAlternatingRowBackgrounds: $showsAlternatingRowBackgrounds,
                showsSymbolsAsText: $showsSymbolsAsText
            )
            SearchEditCommands()
            AppInformationCommands()
            AppHelpCommands()
        }

        Window("Favorite timetables", id: AppWindow.favoriteTimetables) {
            NavigationStack {
                FavoriteTimetablesView()
            }
            .frame(minWidth: 480, minHeight: 520)
        }
        .defaultSize(width: 520, height: 620)
        .defaultPosition(.center)

        Window("About Kaštan", id: AppWindow.information) {
            AppInformationView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        WindowGroup("Service route", id: AppWindow.serviceDetail, for: ServiceSelection.self) { selection in
            if let selection = selection.wrappedValue {
                ServiceDetailWindowContent(
                    selection: selection,
                    client: client,
                    showsItemDetails: showsItemDetails,
                    showsStopNoteText: showsSymbolsAsText
                )
                .environment(\.showsAlternatingRowBackgrounds, showsAlternatingRowBackgrounds)
            }
        }
        .defaultSize(width: ServiceDetailView.defaultWindowWidth, height: 640)

        WindowGroup("Connection detail", id: AppWindow.connectionDetail, for: ConnectionSelection.self) { selection in
            if let selection = selection.wrappedValue {
                ConnectionDetailView(
                    selection: selection,
                    client: client,
                    showsConnectionBadges: showsConnectionBadges,
                    showsItemDetails: showsItemDetails,
                    showsServiceInformationText: showsSymbolsAsText,
                    showsStopNoteText: showsSymbolsAsText
                )
                .environment(\.showsAlternatingRowBackgrounds, showsAlternatingRowBackgrounds)
            }
        }
        .defaultSize(width: ConnectionDetailView.defaultWindowWidth, height: 640)
    }
}
