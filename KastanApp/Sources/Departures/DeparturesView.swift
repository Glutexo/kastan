import AppKit
import Kastan
import SwiftUI

/// Presents a compact macOS station-board search workspace and its returned services.
struct DeparturesView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: DeparturesViewModel
    let client: any TransitDataSource
    let showsItemDetails: Bool
    let showsServiceInformationText: Bool
    let showsStopNoteText: Bool
    let openDepartures: ((DepartureSearchSelection, DepartureSearchOpenDestination) -> Void)?
    let openStationTimetable: ((StationTimetableSelection, StationTimetableOpenDestination) -> Void)?
    @State private var showsSearchShortcuts = SearchShortcutPresentation.isVisible(
        for: NSEvent.modifierFlags
    )

    init(
        model: DeparturesViewModel,
        client: any TransitDataSource,
        showsItemDetails: Bool,
        showsServiceInformationText: Bool,
        showsStopNoteText: Bool,
        openDepartures: ((DepartureSearchSelection, DepartureSearchOpenDestination) -> Void)? = nil,
        openStationTimetable: ((StationTimetableSelection, StationTimetableOpenDestination) -> Void)? = nil
    ) {
        self.model = model
        self.client = client
        self.showsItemDetails = showsItemDetails
        self.showsServiceInformationText = showsServiceInformationText
        self.showsStopNoteText = showsStopNoteText
        self.openDepartures = openDepartures
        self.openStationTimetable = openStationTimetable
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailLayout(availableWidth: geometry.size.width)

            SearchWorkspace(
                layout: layout,
                searchVerticalPadding: model.isSearchFormCollapsed ? 10 : 18,
                canLoadEarlier: model.canLoadEarlier,
                canLoadLater: model.canLoadLater,
                isLoadingEarlier: model.isLoadingEarlier,
                isLoadingLater: model.isLoadingLater,
                loadEarlier: { await model.loadMore(.earlier) },
                loadLater: { await model.loadMore(.later) }
            ) {
                if model.isSearchFormCollapsed {
                    contextualSearchSummaryBar
                    .transition(.opacity)
                } else {
                    searchPanel(stacked: layout.usesStackedSearchControls)
                        .transition(.opacity)
                }
            } resultsContent: {
                resultsPanel
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .animation(.easeInOut(duration: 0.18), value: model.isSearchFormCollapsed)
            .onAppear {
                model.refreshCurrentDateAndTime()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.refreshCurrentDateAndTime()
            }
        }
        .background {
            OptionModifierMonitor(isPressed: $showsSearchShortcuts)
                .frame(width: 0, height: 0)
        }
        .focusedSceneValue(\.searchEditCommandContext, searchEditCommandContext)
        .task {
            await model.loadInitialSelectionIfNeeded()
        }
        .navigationTitle(
            MainWindowTitlePresentation.departures(
                station: model.station,
                isArrival: model.isArrival
            )
        )
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            results
        }
    }

    private func searchPanel(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            JourneySearchHeader(
                timetable: $model.timetable,
                date: $model.date,
                time: $model.time,
                isArrival: $model.isArrival,
                modeLabel: "Board type",
                departureLabel: "Departures",
                arrivalLabel: "Arrivals",
                allowedTimetables: model.timetables,
                usesCurrentDateAndTime: model.usesCurrentDateAndTime,
                selectCurrentDateAndTime: {
                    model.selectCurrentDateAndTime()
                },
                showsCurrentDateAndTimeShortcut: showsSearchShortcuts,
                usesCompactLayout: stacked
            )

            PlaceAutocompleteField(
                title: "Station",
                prompt: "Station or stop",
                text: $model.station,
                selection: $model.stationSelection,
                timetable: model.timetable,
                scope: .stations,
                client: client
            )
            .frame(maxWidth: .infinity)

            searchControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchControls: some View {
        JourneySearchControls(
            isSearching: model.isSearching,
            canSearch: model.canSearch
        ) {
            performSearch()
        }
    }

    private var searchSummary: SearchSummaryPresentation {
        .station(
            name: model.station,
            timetable: model.timetable.appDisplayName,
            date: TransitRequestFormatting.displayDate(from: model.date),
            time: TransitRequestFormatting.displayTime(from: model.time),
            mode: AppLocalization.string(model.isArrival ? "Arrivals" : "Departures")
        )
    }

    private var searchSummaryBar: some View {
        SearchSummaryBar(
            summary: searchSummary,
            systemImage: "list.bullet.rectangle",
            edit: editSearch
        )
    }

    /// Offers both board modes and the station timetable from the compact submitted-search header.
    @ViewBuilder
    private var contextualSearchSummaryBar: some View {
        if headerDepartureAction != nil ||
            headerArrivalAction != nil ||
            headerStationTimetableAction != nil
        {
            searchSummaryBar
                .contentShape(Rectangle())
                .contextMenu {
                    DepartureBoardSearchOpenActions(
                        openDepartures: headerDepartureAction,
                        openArrivals: headerArrivalAction,
                        openStationTimetable: headerStationTimetableAction
                    )
                }
        } else {
            searchSummaryBar
        }
    }

    private var headerDepartureAction: ((DepartureSearchOpenDestination) -> Void)? {
        guard let selection = model.submittedHeaderDepartureSearch(),
              let openDepartures
        else {
            return nil
        }
        return { destination in openDepartures(selection, destination) }
    }

    private var headerArrivalAction: ((DepartureSearchOpenDestination) -> Void)? {
        guard let selection = model.submittedHeaderDepartureSearch(isArrival: true),
              let openDepartures
        else {
            return nil
        }
        return { destination in openDepartures(selection, destination) }
    }

    private var headerStationTimetableAction: ((StationTimetableOpenDestination) -> Void)? {
        guard let selection = model.submittedHeaderStationTimetableSelection(),
              let openStationTimetable
        else {
            return nil
        }
        return { destination in openStationTimetable(selection, destination) }
    }

    private var searchEditCommandContext: SearchEditCommandContext {
        SearchEditCommandContext(
            enabledFillCurrentActions: FillCurrentAction.supportedActions(for: .departures),
            performFillCurrent: fillCurrent,
            swapPlaces: nil
        )
    }

    /// Reveals the editable form before applying a current value from the application menu.
    private func fillCurrent(_ action: FillCurrentAction) {
        guard FillCurrentAction.supportedActions(for: .departures).contains(action) else { return }
        editSearch()

        switch action {
        case .dateAndTime:
            model.selectCurrentDateAndTime()
        case .date:
            model.selectCurrentDate()
        case .time:
            model.selectCurrentTime()
        case .fromPlace, .toPlace:
            break
        }
    }

    private func performSearch() {
        guard model.canSearch else { return }
        model.refreshCurrentDateAndTime()
        withAnimation(.easeInOut(duration: 0.18)) {
            model.collapseSearchForm()
        }
        Task { await model.search() }
    }

    private func editSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            model.revealSearchForm()
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching, model.departures.isEmpty {
            ProgressView("Loading station board…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if model.departures.isEmpty, model.errorMessage == nil {
            EmptyStateView(
                title: "No station board yet",
                systemImage: "tram",
                description: "Choose a station and start a search."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.departures.enumerated()), id: \.element.appIdentity) { index, departure in
                    let station = departure.stationName ?? model.station
                    let resultTimetable = departure.appTimetable(in: client.timetables)
                    let selection = ServiceSelection(
                        id: departure.id,
                        timetable: resultTimetable,
                        highlight: model.isArrival
                            ? ServiceRouteHighlight(toStop: station)
                            : ServiceRouteHighlight(fromStop: station)
                    )
                    DepartureRow(
                        departure: departure,
                        selection: selection,
                        client: client,
                        showsItemDetails: showsItemDetails,
                        showsServiceInformationText: showsServiceInformationText,
                        showsStopNoteText: showsStopNoteText,
                        departureSearchSelection: model.departureSearch(for: departure),
                        arrivalSearchSelection: model.departureSearch(
                            for: departure,
                            isArrival: true
                        ),
                        stationTimetableSelection: model.stationTimetableSelection(for: departure),
                        openDepartures: openDepartures,
                        openStationTimetable: openStationTimetable
                    ) {
                        openWindow(
                            id: AppWindow.serviceDetail,
                            value: selection
                        )
                    }
                    .alternatingRowBackground(at: index)

                    if index < model.departures.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

/// Keeps transfers from a station board in the same order as the main toolbar modes.
struct DepartureBoardSearchOpenActions: View {
    let openDepartures: ((DepartureSearchOpenDestination) -> Void)?
    let openArrivals: ((DepartureSearchOpenDestination) -> Void)?
    let openStationTimetable: ((StationTimetableOpenDestination) -> Void)?

    var availableSections: [AppSection] {
        AppSection.allCases.filter { section in
            switch section {
            case .connections:
                false
            case .departures:
                openDepartures != nil || openArrivals != nil
            case .stationTimetables:
                openStationTimetable != nil
            }
        }
    }

    var body: some View {
        ForEach(availableSections) { section in
            switch section {
            case .connections:
                EmptyView()
            case .departures:
                DepartureArrivalSearchOpenActions(
                    openDepartures: openDepartures,
                    openArrivals: openArrivals
                )
            case .stationTimetables:
                if let openStationTimetable {
                    StationTimetableOpenActions(open: openStationTimetable)
                }
            }
        }
    }
}

private struct DepartureRow: View {
    let departure: TransitDeparture
    let selection: ServiceSelection
    let client: any TransitDataSource
    let showsItemDetails: Bool
    let showsServiceInformationText: Bool
    let showsStopNoteText: Bool
    let departureSearchSelection: DepartureSearchSelection?
    let arrivalSearchSelection: DepartureSearchSelection?
    let stationTimetableSelection: StationTimetableSelection?
    let openDepartures: ((DepartureSearchSelection, DepartureSearchOpenDestination) -> Void)?
    let openStationTimetable: ((StationTimetableSelection, StationTimetableOpenDestination) -> Void)?
    let openService: () -> Void
    @StateObject private var contextMenuModel: ServiceDetailViewModel
    @State private var suppressesPrimaryAction = false
    @State private var isPreviewPresented = false

    init(
        departure: TransitDeparture,
        selection: ServiceSelection,
        client: any TransitDataSource,
        showsItemDetails: Bool,
        showsServiceInformationText: Bool,
        showsStopNoteText: Bool,
        departureSearchSelection: DepartureSearchSelection?,
        arrivalSearchSelection: DepartureSearchSelection?,
        stationTimetableSelection: StationTimetableSelection?,
        openDepartures: ((DepartureSearchSelection, DepartureSearchOpenDestination) -> Void)?,
        openStationTimetable: ((StationTimetableSelection, StationTimetableOpenDestination) -> Void)?,
        openService: @escaping () -> Void
    ) {
        self.departure = departure
        self.selection = selection
        self.client = client
        self.showsItemDetails = showsItemDetails
        self.showsServiceInformationText = showsServiceInformationText
        self.showsStopNoteText = showsStopNoteText
        self.departureSearchSelection = departureSearchSelection
        self.arrivalSearchSelection = arrivalSearchSelection
        self.stationTimetableSelection = stationTimetableSelection
        self.openDepartures = openDepartures
        self.openStationTimetable = openStationTimetable
        self.openService = openService
        _contextMenuModel = StateObject(
            wrappedValue: ServiceDetailViewModel(
                id: selection.serviceID,
                timetable: selection.timetable,
                client: client
            )
        )
    }

    var body: some View {
        Button {
            guard !suppressesPrimaryAction else {
                suppressesPrimaryAction = false
                return
            }
            guard supportsServiceDetails else { return }
            openService()
        } label: {
            HStack(spacing: 14) {
                Text(departure.time)
                    .font(.title3.bold().monospacedDigit())
                    .frame(width: 58, alignment: .leading)

                if let color = Color(idosHTMLColor: departure.lineColor) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 5, height: 38)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text([departure.transportMode?.emoji, departure.lineName].compactMap { $0 }.joined(separator: " "))
                            .font(.headline)
                        if !showsServiceInformationText {
                            ServiceInformationSummary(
                                values: departure.serviceInformation,
                                showsText: false
                            )
                        }
                        Text("→ \(departure.destination)")
                    }
                    if showsServiceInformationText {
                        ServiceInformationSummary(
                            values: departure.serviceInformation,
                            showsText: true
                        )
                    }
                    if let metadata = ResultMetadata.visible(
                        showsDetails: showsItemDetails,
                        ResultMetadata.station(tariffZone: departure.tariffZone, platform: departure.platform),
                        departure.via.map { AppLocalization.string("via %@", $0) },
                        departure.carrier,
                        ResultMetadata.delay(departure.delay)
                    ) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                if contextMenuModel.isPerformingExport {
                    ProgressView()
                        .controlSize(.small)
                } else if supportsServiceDetails {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!supportsServiceDetails && !hasSearchActions)
        .contextMenu {
            if supportsServiceDetails {
                ServiceContextMenuContent(
                    model: contextMenuModel,
                    showPreview: { isPreviewPresented = true },
                    openStationTimetable: stationTimetableAction,
                    openDepartures: departureAction,
                    openArrivals: arrivalAction
                )
            } else if hasSearchActions {
                DepartureBoardSearchOpenActions(
                    openDepartures: departureAction,
                    openArrivals: arrivalAction,
                    openStationTimetable: stationTimetableAction
                )
            }
        }
        .forceClickPreview(
            size: ResultPreviewLayout.serviceSize,
            isEnabled: supportsServiceDetails,
            suppressesPrimaryAction: $suppressesPrimaryAction,
            isPresented: $isPreviewPresented
        ) {
            ServiceDetailView(
                selection: selection,
                client: client,
                showsItemDetails: showsItemDetails,
                showsStopNoteText: showsStopNoteText,
                presentation: .preview
            )
        }
        .resultActionErrorAlert(contextMenuModel.actionError) {
            contextMenuModel.dismissActionError()
        }
    }

    private var supportsServiceDetails: Bool {
        client.descriptor.supports(.serviceDetails)
    }

    private var departureAction: ((DepartureSearchOpenDestination) -> Void)? {
        guard let departureSearchSelection, let openDepartures else { return nil }
        return { destination in openDepartures(departureSearchSelection, destination) }
    }

    private var arrivalAction: ((DepartureSearchOpenDestination) -> Void)? {
        guard let arrivalSearchSelection, let openDepartures else { return nil }
        return { destination in openDepartures(arrivalSearchSelection, destination) }
    }

    private var stationTimetableAction: ((StationTimetableOpenDestination) -> Void)? {
        guard let stationTimetableSelection, let openStationTimetable else { return nil }
        return { destination in openStationTimetable(stationTimetableSelection, destination) }
    }

    private var hasSearchActions: Bool {
        departureAction != nil || arrivalAction != nil || stationTimetableAction != nil
    }
}
