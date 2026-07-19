import Kastan
import SwiftUI

/// Combines a compact macOS search workspace with expandable journey results.
struct ConnectionsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: ConnectionsViewModel
    let client: any IDOSClienting
    @State private var isJourneyOptionsExpanded = false
    @State private var isSearchFormCollapsed = false

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailLayout(availableWidth: geometry.size.width)

            SearchWorkspace(
                layout: layout,
                searchVerticalPadding: isSearchFormCollapsed ? 10 : 18,
                canLoadEarlier: model.canLoadEarlier,
                canLoadLater: model.canLoadLater,
                isLoadingEarlier: model.isLoadingEarlier,
                isLoadingLater: model.isLoadingLater,
                loadEarlier: { await model.loadMore(.earlier) },
                loadLater: { await model.loadMore(.later) }
            ) {
                if isSearchFormCollapsed {
                    SearchSummaryBar(
                        summary: searchSummary,
                        systemImage: "arrow.left.arrow.right",
                        edit: editSearch
                    )
                    .transition(.opacity)
                } else {
                    searchPanel(layout: layout)
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
            .animation(.easeInOut(duration: 0.18), value: isSearchFormCollapsed)
        }
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

    private func searchPanel(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            endpointControls

            Divider()

            searchControls(stacked: layout.usesStackedSearchControls)

            journeyOptions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var endpointControls: some View {
        HStack(alignment: .placeInputCenter, spacing: 10) {
            fromField
                .frame(minWidth: 160, maxWidth: .infinity)
            swapButton
            toField
                .frame(minWidth: 160, maxWidth: .infinity)
        }
    }

    private var fromField: some View {
        PlaceAutocompleteField(
            title: "From",
            prompt: "Departure place",
            text: $model.from,
            selection: $model.fromSelection,
            timetable: model.timetable,
            scope: .places,
            client: client
        )
    }

    private var toField: some View {
        PlaceAutocompleteField(
            title: "To",
            prompt: "Arrival place",
            text: $model.to,
            selection: $model.toSelection,
            timetable: model.timetable,
            scope: .places,
            client: client
        )
    }

    private var swapButton: some View {
        Button {
            model.swapEndpoints()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Swap departure and arrival")
    }

    private func searchControls(stacked: Bool) -> some View {
        JourneySearchControls(
            timetable: $model.timetable,
            date: $model.date,
            time: $model.time,
            isArrival: $model.isArrival,
            modeLabel: "Time means",
            departureLabel: "Departure",
            arrivalLabel: "Arrival",
            isSearching: model.isSearching,
            canSearch: model.canSearch,
            usesStackedLayout: stacked
        ) {
            performSearch()
        }
    }

    private var searchSummary: SearchSummaryPresentation {
        .connection(
            from: model.from,
            to: model.to,
            timetable: model.timetable.appDisplayName,
            date: IDOSRequestFormatting.date(from: model.date),
            time: IDOSRequestFormatting.time(from: model.time),
            mode: AppLocalization.string(model.isArrival ? "Arrival" : "Departure"),
            via: model.viaPlaces.map(\.name),
            transferLimit: model.transferLimitLabel
        )
    }

    private func performSearch() {
        guard model.canSearch else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearchFormCollapsed = true
        }
        Task { await model.search() }
    }

    private func editSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearchFormCollapsed = false
        }
    }

    private var journeyOptions: some View {
        DisclosureGroup(isExpanded: $isJourneyOptionsExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()

                ForEach($model.viaPlaces) { $viaPlace in
                    viaPlaceRow(name: $viaPlace.name, id: viaPlace.id)
                        .padding(.vertical, 6)

                    Divider()
                }

                transfersStepper
                    .padding(.vertical, 8)

                Divider()
            }
            .padding(.top, 8)
        } label: {
            Text("Journey options")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isJourneyOptionsExpanded.toggle()
                    }
                }
        }
        .accessibilityLabel("Journey options")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func viaPlaceRow(name: Binding<String>, id: ViaPlaceEntry.ID) -> some View {
        HStack(spacing: 8) {
            TextField("Via", text: name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 520)

            Spacer(minLength: 0)

            Button {
                model.removeViaPlace(id: id)
            } label: {
                Label("Remove via place", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 14)
            }
            .buttonStyle(.bordered)
            .help("Remove via place")

            Button {
                model.addViaPlace(after: id)
            } label: {
                Label("Add via place", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 14)
            }
            .buttonStyle(.bordered)
            .help("Add via place")
        }
    }

    private var transfersStepper: some View {
        Stepper(value: $model.maximumTransfers, in: 0...10) {
            ZStack(alignment: .leading) {
                Text(AppLocalization.plural("Up to %lld transfers", count: 10))
                    .hidden()
                    .accessibilityHidden(true)
                Text(model.transferLimitLabel)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching, model.connections.isEmpty {
            ProgressView("Searching connections…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if model.connections.isEmpty, model.errorMessage == nil {
            EmptyStateView(
                title: "No connections yet",
                systemImage: "arrow.left.arrow.right",
                description: "Enter a route and start a search."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.connections.enumerated()), id: \.element.id) { index, connection in
                    ConnectionCard(
                        number: index + 1,
                        connection: connection,
                        isPerformingExport: model.importingConnectionID == connection.id ||
                            model.exportingPDFConnectionID == connection.id,
                        openConnection: {
                            openWindow(
                                id: AppWindow.connectionDetail,
                                value: ConnectionSelection(
                                    connection: connection,
                                    timetable: model.timetable
                                )
                            )
                        },
                        openService: { openWindow(id: AppWindow.serviceDetail, value: $0) },
                        addToCalendar: { Task { await model.addToCalendar(connection) } },
                        saveAsPDF: { Task { await model.saveAsPDF(connection) } }
                    )
                }
            }
        }
    }
}

/// Carries a complete connection and its timetable into an independent restorable window.
struct ConnectionSelection: Codable, Hashable, Identifiable {
    let connection: IDOSConnection
    let timetable: IDOSTimetable

    var id: String {
        "\(timetable.slug):\(connection.id)"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.connection == rhs.connection && lhs.timetable == rhs.timetable
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Contains one complete journey and all of its legs in a distinct native result card.
private struct ConnectionCard: View {
    let number: Int?
    let connection: IDOSConnection
    let isPerformingExport: Bool
    let openConnection: (() -> Void)?
    let openService: (ServiceSelection) -> Void
    let addToCalendar: () -> Void
    let saveAsPDF: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let number {
                        Text(AppLocalization.string("Connection %lld", number))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(connection.departureTime) → \(connection.arrivalTime)")
                        .font(.title2.bold().monospacedDigit())
                    Text(connection.duration)
                        .foregroundStyle(.secondary)
                    if connection.legs.count <= 1 {
                        Text("Direct")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    if let openConnection {
                        Button(action: openConnection) {
                            Label("Open connection in new window", systemImage: "macwindow")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Open connection in new window")
                    }
                    Menu {
                        Button {
                            addToCalendar()
                        } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                        Button {
                            saveAsPDF()
                        } label: {
                            Label("Save as PDF", systemImage: "arrow.down.doc")
                        }
                        if let value = connection.shareURL,
                           let url = AppLanguagePreference.localizedIDOSURL(from: value)
                        {
                            ShareLink(item: url) {
                                Label("Share Link", systemImage: "square.and.arrow.up")
                            }
                            Link(destination: url) {
                                Label("Open in IDOS", systemImage: "arrow.up.right.square")
                            }
                        }
                    } label: {
                        if isPerformingExport {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isPerformingExport)
                }

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(connection.departureStation)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(connection.arrivalStation)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(connection.departureStation)
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .foregroundStyle(.secondary)
                            Text(connection.arrivalStation)
                        }
                    }
                }

                if !connection.legs.isEmpty {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(Array(connection.legs.enumerated()), id: \.offset) { index, leg in
                            ConnectionLegRow(leg: leg, openService: openService)
                            if index < connection.legs.count - 1 {
                                Divider()
                                    .padding(.leading, 30)
                            }
                        }
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Shows one complete connection in its own window while retaining all result actions.
struct ConnectionDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var actionsModel: ConnectionsViewModel
    private let selection: ConnectionSelection

    init(selection: ConnectionSelection, client: any IDOSClienting) {
        self.selection = selection
        let actionsModel = ConnectionsViewModel(client: client)
        actionsModel.timetable = selection.timetable
        _actionsModel = StateObject(wrappedValue: actionsModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage = actionsModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                ConnectionCard(
                    number: nil,
                    connection: selection.connection,
                    isPerformingExport: actionsModel.importingConnectionID == selection.connection.id ||
                        actionsModel.exportingPDFConnectionID == selection.connection.id,
                    openConnection: nil,
                    openService: { openWindow(id: AppWindow.serviceDetail, value: $0) },
                    addToCalendar: {
                        Task { await actionsModel.addToCalendar(selection.connection) }
                    },
                    saveAsPDF: {
                        Task { await actionsModel.saveAsPDF(selection.connection) }
                    }
                )
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 420)
        .navigationTitle("\(selection.connection.departureStation) → \(selection.connection.arrivalStation)")
    }
}

private struct ConnectionLegRow: View {
    let leg: IDOSConnectionLeg
    let openService: (ServiceSelection) -> Void

    var body: some View {
        Button {
            if let id = leg.id {
                openService(
                    ServiceSelection(
                        id: id,
                        highlight: ServiceRouteHighlight(
                            fromStop: leg.fromStation,
                            toStop: leg.toStation
                        )
                    )
                )
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 3) {
                    if let color = Color(idosHTMLColor: leg.color) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: 5, height: 38)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.4))
                            .frame(width: 5, height: 38)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text([leg.transportMode?.emoji, leg.name].compactMap { $0 }.joined(separator: " "))
                            .font(.headline)
                        Spacer()
                        if leg.id != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(leg.departureTime)
                                .font(.body.bold().monospacedDigit())
                                .frame(width: 48, alignment: .leading)
                            Text(leg.fromStation)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(leg.arrivalTime)
                                .font(.body.bold().monospacedDigit())
                                .frame(width: 48, alignment: .leading)
                            Text(leg.toStation)
                        }
                    }
                    if let metadata = ResultMetadata.joined(
                        leg.carrier,
                        ResultMetadata.delay(leg.delay),
                        ResultMetadata.station(tariffZone: leg.fromTariffZone, platform: leg.fromPlatform)
                    ) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(leg.id == nil)
    }
}
