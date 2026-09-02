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

/// Performs native tab and window operations for the active macOS window.
@MainActor
enum AppWindowActions {
    /// Creates a fresh main search window and joins it to the active window as a native tab.
    static func newTab(openMainWindow: () -> Void) {
        guard let sourceWindow = NSApplication.shared.keyWindow else { return }
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: AppWindow.main)
            }
            .keyboardShortcut("n")

            Button("New Tab") {
                AppWindowActions.newTab {
                    openWindow(id: AppWindow.main)
                }
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
    @Binding var showsConnectionBadges: Bool
    @Binding var showsItemDetails: Bool
    @Binding var showsAlternatingRowBackgrounds: Bool
    @Binding var showsSymbolsAsText: Bool
    @Binding var showsAddressSuggestions: Bool
    @Binding var showsBoroughSuggestions: Bool
    @Binding var showsMunicipalitySuggestions: Bool
    let supportsPlaceSuggestions: Bool

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

            if supportsPlaceSuggestions {
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

    private var client: any TransitDataSource {
        dataSources.defaultDataSource
    }

    init() {
        SymbolTextPreference.migrateLegacyValues()
        ApplicationMainMenu.shared.install()
    }

    var body: some Scene {
        WindowGroup(id: AppWindow.main) {
            ContentView(
                client: client,
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
        }
        .defaultSize(width: Self.defaultMainWindowWidth, height: 720)
        .commands {
            AppWindowCommands()
            ResultDetailCommands()
            AppSectionCommands(
                showsConnectionBadges: $showsConnectionBadges,
                showsItemDetails: $showsItemDetails,
                showsAlternatingRowBackgrounds: $showsAlternatingRowBackgrounds,
                showsSymbolsAsText: $showsSymbolsAsText,
                showsAddressSuggestions: $showsAddressSuggestions,
                showsBoroughSuggestions: $showsBoroughSuggestions,
                showsMunicipalitySuggestions: $showsMunicipalitySuggestions,
                supportsPlaceSuggestions: client.descriptor.supports(.placeSuggestions)
            )
            SearchEditCommands()
            AppInformationCommands()
            AppHelpCommands()
        }

        Window("Favorite timetables", id: AppWindow.favoriteTimetables) {
            NavigationStack {
                FavoriteTimetablesView(timetables: client.timetables)
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
