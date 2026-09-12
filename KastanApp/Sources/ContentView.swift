import AppKit
import Kastan
import SwiftUI

/// The three provider-backed search modes available from the main window toolbar.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case connections
    case departures
    case stationTimetables

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .connections:
            "Connections"
        case .departures:
            "Departures"
        case .stationTimetables:
            "Station timetables"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }

    var systemImage: String {
        switch self {
        case .connections:
            "arrow.left.arrow.right"
        case .departures:
            "list.bullet.rectangle"
        case .stationTimetables:
            "calendar"
        }
    }

    /// Associates each search surface with the capability explicitly advertised by the active provider.
    var capability: TransitDataSourceCapability {
        switch self {
        case .connections:
            .connections
        case .departures:
            .departures
        case .stationTimetables:
            .stationTimetables
        }
    }

    static func available(for descriptor: TransitDataSourceDescriptor) -> [Self] {
        allCases.filter { descriptor.supports($0.capability) }
    }
}

/// Exposes the active window's search mode to app-level menu commands.
struct AppSectionSelectionKey: FocusedValueKey {
    typealias Value = Binding<AppSection>
}

struct AvailableAppSectionsKey: FocusedValueKey {
    typealias Value = Set<AppSection>
}

extension FocusedValues {
    var appSectionSelection: Binding<AppSection>? {
        get { self[AppSectionSelectionKey.self] }
        set { self[AppSectionSelectionKey.self] = newValue }
    }


    var availableAppSections: Set<AppSection>? {
        get { self[AvailableAppSectionsKey.self] }
        set { self[AvailableAppSectionsKey.self] = newValue }
    }
}

/// Exposes the focused main window's provider contract to capability-sensitive app commands.
struct ActiveDataSourceDescriptorKey: FocusedValueKey {
    typealias Value = TransitDataSourceDescriptor
}

extension FocusedValues {
    var activeDataSourceDescriptor: TransitDataSourceDescriptor? {
        get { self[ActiveDataSourceDescriptorKey.self] }
        set { self[ActiveDataSourceDescriptorKey.self] = newValue }
    }
}

/// Converts the detail column's measured width into stable responsive layout decisions.
struct DetailLayout {
    private static let compactPaddingBreakpoint: CGFloat = 650
    private static let stackedSearchBreakpoint: CGFloat = 820
    private static let compactHorizontalPadding: CGFloat = 16
    private static let regularHorizontalPadding: CGFloat = 24

    let availableWidth: CGFloat

    var containerWidth: CGFloat {
        max(availableWidth, 0)
    }

    var horizontalPadding: CGFloat {
        availableWidth < Self.compactPaddingBreakpoint
            ? Self.compactHorizontalPadding
            : Self.regularHorizontalPadding
    }

    var contentWidth: CGFloat {
        max(containerWidth - (2 * horizontalPadding), 0)
    }

    var usesStackedSearchControls: Bool {
        contentWidth < Self.stackedSearchBreakpoint
    }

    /// Converts a required full-width search row into the narrowest window that retains its active padding.
    static func minimumAvailableWidth(fittingContentWidth requiredContentWidth: CGFloat) -> CGFloat {
        let requiredContentWidth = max(requiredContentWidth, 0)
        let compactWidth = ceil(requiredContentWidth + (2 * compactHorizontalPadding))
        if compactWidth < compactPaddingBreakpoint {
            return compactWidth
        }

        return ceil(requiredContentWidth + (2 * regularHorizontalPadding))
    }
}

private struct SearchResultViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Keeps search controls visible while giving only the result area the remaining scrollable space.
struct SearchWorkspace<SearchContent: View, ResultsContent: View>: View {
    let layout: DetailLayout
    private let searchVerticalPadding: CGFloat
    private let canLoadEarlier: Bool
    private let canLoadLater: Bool
    private let isLoadingEarlier: Bool
    private let isLoadingLater: Bool
    private let loadEarlier: (@MainActor () async -> Void)?
    private let loadLater: (@MainActor () async -> Void)?
    private let searchContent: SearchContent
    private let resultsContent: ResultsContent
    @State private var viewportHeight: CGFloat = 0

    init(
        layout: DetailLayout,
        searchVerticalPadding: CGFloat = 18,
        canLoadEarlier: Bool = false,
        canLoadLater: Bool = false,
        isLoadingEarlier: Bool = false,
        isLoadingLater: Bool = false,
        loadEarlier: (@MainActor () async -> Void)? = nil,
        loadLater: (@MainActor () async -> Void)? = nil,
        @ViewBuilder searchContent: () -> SearchContent,
        @ViewBuilder resultsContent: () -> ResultsContent
    ) {
        self.layout = layout
        self.searchVerticalPadding = searchVerticalPadding
        self.canLoadEarlier = canLoadEarlier
        self.canLoadLater = canLoadLater
        self.isLoadingEarlier = isLoadingEarlier
        self.isLoadingLater = isLoadingLater
        self.loadEarlier = loadEarlier
        self.loadLater = loadLater
        self.searchContent = searchContent()
        self.resultsContent = resultsContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            searchContent
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, searchVerticalPadding)
                .frame(width: layout.containerWidth, alignment: .topLeading)
                .frame(width: layout.availableWidth, alignment: .topLeading)
                .background(.bar)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if isLoadingEarlier {
                        ProgressView("Loading earlier results…")
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    }

                    resultsContent
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.vertical, 20)
                        .frame(width: layout.containerWidth, alignment: .topLeading)
                        .frame(width: layout.availableWidth, alignment: .topLeading)

                    if isLoadingLater {
                        ProgressView("Loading later results…")
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: viewportHeight + 2,
                    alignment: .top
                )
                .background {
                    SearchResultPullMonitor(
                        canLoadEarlier: canLoadEarlier,
                        canLoadLater: canLoadLater,
                        isLoadingEarlier: isLoadingEarlier,
                        isLoadingLater: isLoadingLater,
                        load: requestPage
                    )
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SearchResultViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(SearchResultViewportHeightPreferenceKey.self) { height in
                viewportHeight = height
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func requestPage(_ edge: SearchResultPagingEdge) {
        switch edge {
        case .earlier:
            guard let loadEarlier else { return }
            Task { @MainActor in await loadEarlier() }
        case .later:
            guard let loadLater else { return }
            Task { @MainActor in await loadLater() }
        }
    }
}

/// Owns every provider-specific model that must be discarded together when a main window changes source.
@MainActor
final class AppDataSourceWorkspace: ObservableObject, Identifiable {
    let id = UUID()
    let client: any TransitDataSource
    let availableSections: [AppSection]
    let connectionsModel: ConnectionsViewModel
    let departuresModel: DeparturesViewModel
    let stationTimetablesModel: StationTimetablesViewModel
    @Published var selection: AppSection

    init(
        client: any TransitDataSource,
        initialConnectionSelection: ConnectionSearchSelection? = nil,
        initialStationTimetableSelection: StationTimetableSelection? = nil,
        initialDepartureSelection: DepartureSearchSelection? = nil,
        initialDepartureSearch: ResolvedDepartureSearch? = nil,
        lastSelectedTimetable: LastSelectedTimetable? = nil
    ) {
        self.client = client
        availableSections = AppSection.available(for: client.descriptor)
        let preferredTimetable = lastSelectedTimetable?.timetable(
            for: client.descriptor.id,
            in: client.timetables
        )
        let rememberTimetable: (TransitTimetable) -> Void = { timetable in
            lastSelectedTimetable?.remember(timetable)
        }
        let opensConnections = initialConnectionSelection?.dataSourceID == client.descriptor.id &&
            availableSections.contains(.connections)
        let opensStationTimetable = initialStationTimetableSelection?.dataSourceID == client.descriptor.id &&
            availableSections.contains(.stationTimetables)
        let opensResolvedDepartures = initialDepartureSearch?.dataSourceID == client.descriptor.id &&
            availableSections.contains(.departures)
        let opensSelectedDepartures = !opensResolvedDepartures &&
            initialDepartureSelection?.dataSourceID == client.descriptor.id &&
            availableSections.contains(.departures)
        let opensDepartures = opensResolvedDepartures || opensSelectedDepartures
        selection = opensConnections
            ? .connections
            : opensDepartures
                ? .departures
                : opensStationTimetable ? .stationTimetables : availableSections.first ?? .connections
        connectionsModel = ConnectionsViewModel(
            client: client,
            initialSelection: opensConnections ? initialConnectionSelection : nil,
            preferredTimetable: preferredTimetable,
            rememberTimetable: rememberTimetable
        )
        departuresModel = DeparturesViewModel(
            client: client,
            initialSelection: opensSelectedDepartures ? initialDepartureSelection : nil,
            preferredTimetable: preferredTimetable,
            rememberTimetable: rememberTimetable
        )
        stationTimetablesModel = StationTimetablesViewModel(
            client: client,
            initialSelection: opensStationTimetable ? initialStationTimetableSelection : nil,
            preferredTimetable: preferredTimetable,
            rememberTimetable: rememberTimetable
        )
        if opensResolvedDepartures, let initialDepartureSearch {
            departuresModel.present(initialDepartureSearch)
        }
    }

    /// Replaces this window's journey form with a station-timetable departure transfer.
    @discardableResult
    func showConnections(_ transferredSelection: ConnectionSearchSelection) -> Bool {
        guard availableSections.contains(.connections),
              connectionsModel.present(transferredSelection)
        else {
            return false
        }

        selection = .connections
        return true
    }

    /// Moves the completed connection route into the editable Station Timetables form in this window.
    @discardableResult
    func showStationTimetableForConnectionSearch() -> Bool {
        guard let selection = stationTimetableSelectionForConnectionSearch() else { return false }
        return showStationTimetable(selection)
    }

    /// Replaces this window's station-timetable form with a connection or service transfer.
    @discardableResult
    func showStationTimetable(_ transferredSelection: StationTimetableSelection) -> Bool {
        guard availableSections.contains(.stationTimetables),
              stationTimetablesModel.present(transferredSelection)
        else {
            return false
        }

        selection = .stationTimetables
        return true
    }

    /// Moves a connection result's complete departure-board query into this window.
    @discardableResult
    func showDepartures(_ transferredSelection: DepartureSearchSelection) -> Bool {
        guard availableSections.contains(.departures),
              departuresModel.present(transferredSelection)
        else {
            return false
        }

        selection = .departures
        return true
    }

    /// Moves an already resolved station board into Departures without repeating its provider request.
    @discardableResult
    func showDepartures(_ search: ResolvedDepartureSearch) -> Bool {
        guard availableSections.contains(.departures),
              search.dataSourceID == client.descriptor.id
        else {
            return false
        }

        departuresModel.present(search)
        selection = .departures
        return true
    }

    /// Builds the editable station-timetable draft transferred into another main window or tab.
    func stationTimetableSelectionForConnectionSearch() -> StationTimetableSelection? {
        guard availableSections.contains(.stationTimetables) else { return nil }
        return StationTimetableSelectionFactory.search(
            timetable: connectionsModel.timetable,
            from: connectionsModel.from,
            to: connectionsModel.to,
            serviceDate: TransitRequestFormatting.serviceDate(from: connectionsModel.date),
            client: client
        )
    }
}

/// Keeps a source choice local to one main window and replaces all provider-owned state atomically.
@MainActor
final class AppDataSourceSelection: ObservableObject {
    let registry: TransitDataSourceRegistry
    let descriptors: [TransitDataSourceDescriptor]
    let timetables: [TransitTimetable]
    @Published private(set) var workspace: AppDataSourceWorkspace
    private let lastSelectedTimetable: LastSelectedTimetable?

    init(
        registry: TransitDataSourceRegistry,
        lastSelectedTimetable: LastSelectedTimetable? = nil,
        initialDataSourceID: TransitDataSourceID? = nil,
        initialConnectionSelection: ConnectionSearchSelection? = nil,
        initialStationTimetableSelection: StationTimetableSelection? = nil,
        initialDepartureSelection: DepartureSearchSelection? = nil,
        initialDepartureSearch: ResolvedDepartureSearch? = nil
    ) {
        self.registry = registry
        self.lastSelectedTimetable = lastSelectedTimetable
        descriptors = registry.descriptors
        timetables = registry.descriptors.flatMap { descriptor in
            registry.dataSource(for: descriptor.id)?.timetables ?? []
        }
        let initialDataSource = initialDataSourceID.flatMap(registry.dataSource(for:))
            ?? registry.defaultDataSource
        workspace = AppDataSourceWorkspace(
            client: initialDataSource,
            initialConnectionSelection: initialConnectionSelection,
            initialStationTimetableSelection: initialStationTimetableSelection,
            initialDepartureSelection: initialDepartureSelection,
            initialDepartureSearch: initialDepartureSearch,
            lastSelectedTimetable: lastSelectedTimetable
        )
    }

    var selectedDataSourceID: TransitDataSourceID {
        workspace.client.descriptor.id
    }

    var showsSourceSelector: Bool {
        descriptors.count > 1 && descriptors.contains { $0.id == selectedDataSourceID }
    }

    /// Accepts ordinary picker choices and creates fresh search state for every provider change.
    ///
    /// Explicit-only providers can initialize a window after the corresponding special action, but never leak into
    /// the ordinary toolbar picker.
    @discardableResult
    func selectDataSource(_ id: TransitDataSourceID) -> Bool {
        guard id != selectedDataSourceID,
              descriptors.contains(where: { $0.id == id }),
              let dataSource = registry.dataSource(for: id)
        else {
            return false
        }

        workspace = AppDataSourceWorkspace(
            client: dataSource,
            lastSelectedTimetable: lastSelectedTimetable
        )
        return true
    }
}

/// Observes the lifetime of exactly one main AppKit window without conflating view disappearance with closure.
struct MainWindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AttachmentView, context: Context) {
        context.coordinator.onClose = onClose
        nsView.coordinator = context.coordinator
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
    final class Coordinator: NSObject {
        var onClose: @MainActor () -> Void
        private weak var window: NSWindow?

        init(onClose: @escaping @MainActor () -> Void) {
            self.onClose = onClose
        }

        func install(on window: NSWindow?) {
            guard self.window !== window else { return }
            uninstall()
            guard let window else { return }

            self.window = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        func uninstall() {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: window
            )
            window = nil
        }

        @objc private func windowWillClose(_ notification: Notification) {
            onClose()
        }
    }
}

/// Selects one provider per main window while retaining independent state among its search modes.
struct ContentView: View {
    @Binding private var sceneValue: MainWindowSceneValue
    @StateObject private var dataSourceSelection: AppDataSourceSelection
    private let lastClosedDataSource: LastClosedMainWindowDataSource
    private let showsConnectionBadges: Bool
    private let showsItemDetails: Bool
    private let showsServiceInformationText: Bool
    private let showsStopNoteText: Bool

    init(
        sceneValue: Binding<MainWindowSceneValue>,
        dataSources: TransitDataSourceRegistry,
        lastClosedDataSource: LastClosedMainWindowDataSource,
        lastSelectedTimetable: LastSelectedTimetable,
        showsConnectionBadges: Bool,
        showsItemDetails: Bool,
        showsServiceInformationText: Bool,
        showsStopNoteText: Bool
    ) {
        let initialDepartureSearch = ResolvedDepartureSearchTransferStore.shared.search(
            for: sceneValue.wrappedValue.initialDepartureSearchTransferID
        )
        _sceneValue = sceneValue
        _dataSourceSelection = StateObject(
            wrappedValue: AppDataSourceSelection(
                registry: dataSources,
                lastSelectedTimetable: lastSelectedTimetable,
                initialDataSourceID: sceneValue.wrappedValue.dataSourceID,
                initialConnectionSelection: sceneValue.wrappedValue.initialConnectionSelection,
                initialStationTimetableSelection: sceneValue.wrappedValue.initialStationTimetableSelection,
                initialDepartureSelection: sceneValue.wrappedValue.initialDepartureSelection,
                initialDepartureSearch: initialDepartureSearch
            )
        )
        self.lastClosedDataSource = lastClosedDataSource
        self.showsConnectionBadges = showsConnectionBadges
        self.showsItemDetails = showsItemDetails
        self.showsServiceInformationText = showsServiceInformationText
        self.showsStopNoteText = showsStopNoteText
    }

    var body: some View {
        ProviderSearchWorkspaceView(
            workspace: dataSourceSelection.workspace,
            dataSourceDescriptors: dataSourceSelection.descriptors,
            selectedDataSourceID: Binding(
                get: { dataSourceSelection.selectedDataSourceID },
                set: { dataSourceID in
                    guard dataSourceSelection.selectDataSource(dataSourceID) else { return }
                    sceneValue.dataSourceID = dataSourceID
                }
            ),
            allowsDataSourceSelection: dataSourceSelection.showsSourceSelector,
            showsConnectionBadges: showsConnectionBadges,
            showsItemDetails: showsItemDetails,
            showsServiceInformationText: showsServiceInformationText,
            showsStopNoteText: showsStopNoteText
        )
        .id(dataSourceSelection.workspace.id)
        .background {
            MainWindowCloseObserver {
                lastClosedDataSource.remember(dataSourceSelection.selectedDataSourceID)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            // A restored provider can disappear between app versions. Keep the persisted scene value aligned with
            // the registry fallback selected by the workspace in that case.
            if sceneValue.dataSourceID != dataSourceSelection.selectedDataSourceID {
                sceneValue.dataSourceID = dataSourceSelection.selectedDataSourceID
            }
            if sceneValue.initialConnectionSelection != nil {
                sceneValue.initialConnectionSelection = nil
            }
            if sceneValue.initialStationTimetableSelection != nil {
                sceneValue.initialStationTimetableSelection = nil
            }
            if sceneValue.initialDepartureSelection != nil {
                sceneValue.initialDepartureSelection = nil
            }
            if let transferID = sceneValue.initialDepartureSearchTransferID {
                sceneValue.initialDepartureSearchTransferID = nil
                ResolvedDepartureSearchTransferStore.shared.discard(transferID)
            }
        }
    }
}

/// Renders one immutable provider context; replacing this view also removes its transient SwiftUI state.
private struct ProviderSearchWorkspaceView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var workspace: AppDataSourceWorkspace
    let dataSourceDescriptors: [TransitDataSourceDescriptor]
    @Binding var selectedDataSourceID: TransitDataSourceID
    let allowsDataSourceSelection: Bool
    let showsConnectionBadges: Bool
    let showsItemDetails: Bool
    let showsServiceInformationText: Bool
    let showsStopNoteText: Bool

    private var client: any TransitDataSource { workspace.client }

    var body: some View {
        selectedContent
            .background {
                MainWindowToolbarInstaller(
                    selection: $workspace.selection,
                    sections: workspace.availableSections,
                    dataSourceSelection: $selectedDataSourceID,
                    dataSourceDescriptors: dataSourceDescriptors,
                    allowsDataSourceSelection: allowsDataSourceSelection,
                    openFavoriteTimetables: { openWindow(id: AppWindow.favoriteTimetables) },
                    openAppInformation: { openWindow(id: AppWindow.information) }
                )
            }
            .focusedSceneValue(\.appSectionSelection, $workspace.selection)
            .focusedSceneValue(\.availableAppSections, Set(workspace.availableSections))
            .focusedSceneValue(\.activeDataSourceDescriptor, client.descriptor)
    }

    @ViewBuilder
    private var selectedContent: some View {
        if !workspace.availableSections.contains(workspace.selection) {
            EmptyStateView(
                title: "Search unavailable",
                systemImage: "exclamationmark.magnifyingglass",
                description: "The selected data source does not provide a search mode supported by this app."
            )
        } else {
            switch workspace.selection {
            case .connections:
                ConnectionsView(
                    model: workspace.connectionsModel,
                    client: client,
                    showsConnectionBadges: showsConnectionBadges,
                    showsItemDetails: showsItemDetails,
                    showsServiceInformationText: showsServiceInformationText,
                    showsStopNoteText: showsStopNoteText,
                    openStationTimetable: workspace.availableSections.contains(.stationTimetables)
                        ? { selection, destination in
                            openStationTimetable(selection, at: destination)
                        }
                        : nil,
                    openDepartures: workspace.availableSections.contains(.departures)
                        ? { selection, destination in
                            openDepartures(selection, at: destination)
                        }
                        : nil
                )
            case .departures:
                DeparturesView(
                    model: workspace.departuresModel,
                    client: client,
                    showsItemDetails: showsItemDetails,
                    showsServiceInformationText: showsServiceInformationText,
                    showsStopNoteText: showsStopNoteText
                )
            case .stationTimetables:
                StationTimetablesView(
                    model: workspace.stationTimetablesModel,
                    client: client,
                    showsItemDetails: showsItemDetails,
                    showsStopNoteText: showsStopNoteText,
                    showDepartureSearch: { selection, destination in
                        openDepartures(selection, at: destination)
                    },
                    showInDepartures: { search, destination in
                        openDepartures(search, at: destination)
                    },
                    showInConnections: { selection, destination in
                        openConnections(selection, at: destination)
                    }
                )
            }
        }
    }

    /// Starts a station-timetable minute's journey search here or in an independent scene.
    private func openConnections(
        _ selection: ConnectionSearchSelection,
        at destination: ConnectionSearchOpenDestination
    ) {
        switch destination {
        case .currentWindow:
            _ = workspace.showConnections(selection)
        case .newWindow, .newTab:
            guard selection.dataSourceID == client.descriptor.id,
                  workspace.availableSections.contains(.connections)
            else {
                return
            }
            let sceneValue = MainWindowSceneValue(
                dataSourceID: selection.dataSourceID,
                initialConnectionSelection: selection
            )

            if destination == .newTab {
                AppWindowActions.newTab {
                    openWindow(id: AppWindow.main, value: sceneValue)
                }
            } else {
                openWindow(id: AppWindow.main, value: sceneValue)
            }
        }
    }

    /// Reuses a prepared result in place or seeds an independent native tab or window.
    private func openStationTimetable(
        _ selection: StationTimetableSelection,
        at destination: StationTimetableOpenDestination
    ) {
        switch destination {
        case .currentTab:
            _ = workspace.showStationTimetable(selection)
        case .newTab, .newWindow:
            let sceneValue = MainWindowSceneValue(
                dataSourceID: selection.dataSourceID,
                initialStationTimetableSelection: selection
            )

            if destination == .newTab {
                AppWindowActions.newTab {
                    openWindow(id: AppWindow.main, value: sceneValue)
                }
            } else {
                openWindow(id: AppWindow.main, value: sceneValue)
            }
        }
    }

    /// Starts a connection result's departure-board query here or in an independent scene.
    private func openDepartures(
        _ selection: DepartureSearchSelection,
        at destination: DepartureSearchOpenDestination
    ) {
        switch destination {
        case .currentWindow:
            _ = workspace.showDepartures(selection)
        case .newWindow, .newTab:
            guard selection.dataSourceID == client.descriptor.id,
                  workspace.availableSections.contains(.departures)
            else {
                return
            }
            let sceneValue = MainWindowSceneValue(
                dataSourceID: selection.dataSourceID,
                initialDepartureSelection: selection
            )

            if destination == .newTab {
                AppWindowActions.newTab {
                    openWindow(id: AppWindow.main, value: sceneValue)
                }
            } else {
                openWindow(id: AppWindow.main, value: sceneValue)
            }
        }
    }

    /// Reuses the resolved station board here or transfers its complete provider state to another scene.
    private func openDepartures(
        _ search: ResolvedDepartureSearch,
        at destination: DepartureSearchOpenDestination
    ) {
        switch destination {
        case .currentWindow:
            _ = workspace.showDepartures(search)
        case .newWindow, .newTab:
            guard let dataSourceID = search.dataSourceID,
                  dataSourceID == client.descriptor.id,
                  workspace.availableSections.contains(.departures)
            else {
                return
            }
            let transferID = ResolvedDepartureSearchTransferStore.shared.store(search)
            let sceneValue = MainWindowSceneValue(
                dataSourceID: dataSourceID,
                initialDepartureSearchTransferID: transferID
            )

            if destination == .newTab {
                AppWindowActions.newTab {
                    openWindow(id: AppWindow.main, value: sceneValue)
                }
            } else {
                openWindow(id: AppWindow.main, value: sceneValue)
            }
        }
    }
}
