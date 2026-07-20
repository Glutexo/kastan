import AppKit
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
            via: model.viaPlaceNames,
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

                ForEach($model.journeyOptions) { $journeyOption in
                    journeyOptionRow(option: $journeyOption)
                        .padding(.vertical, 6)

                    Divider()
                }
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

    private func journeyOptionRow(option: Binding<JourneyOptionEntry>) -> some View {
        HStack(spacing: 8) {
            journeyOptionKindMenu(option: option)

            journeyOptionValue(option: option)

            Spacer(minLength: 0)

            if model.journeyOptions.count > 1 {
                Button {
                    model.removeJourneyOption(id: option.wrappedValue.id)
                } label: {
                    Label("Remove journey option", systemImage: "minus")
                        .labelStyle(.iconOnly)
                        .frame(width: 20, height: 14)
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Remove journey option")
            }

            Button {
                model.addJourneyOption(after: option.wrappedValue.id)
            } label: {
                Label("Add journey option", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 14)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .help("Add journey option")
        }
        .frame(height: 28)
    }

    /// Keeps the visible menu as wide as the longest supported condition, including unavailable singleton types.
    private func journeyOptionKindMenu(option: Binding<JourneyOptionEntry>) -> some View {
        JourneyOptionKindPicker(
            selection: option.kind,
            availableKinds: model.availableJourneyOptionKinds(for: option.wrappedValue.id)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func journeyOptionValue(option: Binding<JourneyOptionEntry>) -> some View {
        switch option.wrappedValue.kind {
        case .via:
            TextField("Via place", text: option.viaPlace)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 520)
                .layoutPriority(1)
        case .maximumTransfers:
            Stepper(
                value: maximumTransfersBinding(for: option),
                in: ConnectionsViewModel.maximumTransferRange
            ) {
                TextField(
                    "Maximum number of transfers",
                    value: maximumTransfersBinding(for: option),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(width: 40)
            }
            .fixedSize()
            .accessibilityLabel("Maximum number of transfers")
        }
    }

    /// Preserves the former stepper's accepted range while presenting the requested number field.
    private func maximumTransfersBinding(for option: Binding<JourneyOptionEntry>) -> Binding<Int> {
        Binding(
            get: { option.wrappedValue.maximumTransfers },
            set: { newValue in
                option.wrappedValue.maximumTransfers = min(
                    max(newValue, ConnectionsViewModel.maximumTransferRange.lowerBound),
                    ConnectionsViewModel.maximumTransferRange.upperBound
                )
            }
        )
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
                        showsActionMenu: true,
                        timeFrameCoordinateSpace: nil,
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

/// Bridges the journey-condition selector to the native popup control while retaining a stable catalog width.
struct JourneyOptionKindPicker: NSViewRepresentable {
    @Binding var selection: JourneyOptionKind
    let availableKinds: [JourneyOptionKind]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> StableWidthPopUpButton {
        let button = StableWidthPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectKind(_:))
        button.setAccessibilityLabel(AppLocalization.string("Journey option"))
        return button
    }

    func updateNSView(_ button: StableWidthPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        button.sizingTitles = JourneyOptionKind.allCases.map(\.localizedTitle)

        let representedKinds = button.itemArray.compactMap { item in
            (item.representedObject as? String).flatMap(JourneyOptionKind.init(rawValue:))
        }
        if representedKinds != availableKinds {
            button.removeAllItems()
            for kind in availableKinds {
                button.addItem(withTitle: kind.localizedTitle)
                button.lastItem?.representedObject = kind.rawValue
            }
        }

        if let index = availableKinds.firstIndex(of: selection) {
            button.selectItem(at: index)
        }
        button.setAccessibilityValue(selection.localizedTitle)
        button.invalidateIntrinsicContentSize()
    }

    /// Passes the selected native menu item back into the SwiftUI row binding.
    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<JourneyOptionKind>

        init(selection: Binding<JourneyOptionKind>) {
            self.selection = selection
        }

        @objc func selectKind(_ sender: NSPopUpButton) {
            guard let rawValue = sender.selectedItem?.representedObject as? String,
                  let kind = JourneyOptionKind(rawValue: rawValue)
            else { return }

            selection.wrappedValue = kind
        }
    }
}

/// Adds the widest catalog title to the native popup button's own chrome-derived intrinsic width.
final class StableWidthPopUpButton: NSPopUpButton {
    var sizingTitles: [String] = [] {
        didSet {
            guard sizingTitles != oldValue else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        let nativeSize = super.intrinsicContentSize
        guard let selectedTitle = titleOfSelectedItem, !sizingTitles.isEmpty else {
            return nativeSize
        }

        let selectedTitleWidth = measuredWidth(of: selectedTitle)
        let widestTitleWidth = sizingTitles.map(measuredWidth).max() ?? selectedTitleWidth
        let chromeWidth = max(0, nativeSize.width - selectedTitleWidth)
        return NSSize(width: ceil(chromeWidth + widestTitleWidth), height: nativeSize.height)
    }

    private func measuredWidth(of title: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]
        return (title as NSString).size(withAttributes: attributes).width
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

/// Moves a connection's time range into its window title exactly when the content label has scrolled away.
enum ConnectionWindowTitlePresentation {
    static func title(for connection: IDOSConnection, timeIsUnderTitle: Bool) -> String {
        let route = "\(connection.departureStation) → \(connection.arrivalStation)"
        guard timeIsUnderTitle else { return route }

        return "\(route) · \(connection.departureTime) → \(connection.arrivalTime)"
    }

    static func timeIsUnderTitle(frame: CGRect?) -> Bool {
        (frame?.maxY ?? 1) <= 0
    }
}

private struct ConnectionTimeFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// Contains one complete journey and all of its legs in a distinct native result card.
private struct ConnectionCard: View {
    let number: Int?
    let connection: IDOSConnection
    let isPerformingExport: Bool
    let showsActionMenu: Bool
    let timeFrameCoordinateSpace: String?
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
                        .background {
                            if let timeFrameCoordinateSpace {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ConnectionTimeFramePreferenceKey.self,
                                        value: geometry.frame(in: .named(timeFrameCoordinateSpace))
                                    )
                                }
                            }
                        }
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
                    if showsActionMenu {
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

/// Defines the actions shown as individual controls in an independent connection window's toolbar.
enum ConnectionDetailToolbarAction: CaseIterable, Hashable, Identifiable {
    case addToCalendar
    case saveAsPDF
    case shareLink
    case openInIDOS

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .addToCalendar:
            "Add to Calendar"
        case .saveAsPDF:
            "Save as PDF"
        case .shareLink:
            "Share Link"
        case .openInIDOS:
            "Open in IDOS"
        }
    }

    var systemImage: String {
        switch self {
        case .addToCalendar:
            "calendar.badge.plus"
        case .saveAsPDF:
            "arrow.down.doc"
        case .shareLink:
            "square.and.arrow.up"
        case .openInIDOS:
            "arrow.up.right.square"
        }
    }

    static func availableActions(hasPermanentLink: Bool) -> [Self] {
        hasPermanentLink ? allCases : [.addToCalendar, .saveAsPDF]
    }
}

/// Shows one complete connection in its own window with result actions in the native toolbar.
struct ConnectionDetailView: View {
    private static let scrollCoordinateSpace = "connection-detail-scroll"

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @StateObject private var actionsModel: ConnectionsViewModel
    @State private var timeIsUnderTitle = false
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
                    showsActionMenu: false,
                    timeFrameCoordinateSpace: Self.scrollCoordinateSpace,
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
        .coordinateSpace(name: Self.scrollCoordinateSpace)
        .onPreferenceChange(ConnectionTimeFramePreferenceKey.self) { frame in
            let newValue = ConnectionWindowTitlePresentation.timeIsUnderTitle(frame: frame)
            if timeIsUnderTitle != newValue {
                timeIsUnderTitle = newValue
            }
        }
        .onAppear {
            timeIsUnderTitle = false
        }
        .frame(minWidth: 620, minHeight: 420)
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(
                    ConnectionDetailToolbarAction.availableActions(
                        hasPermanentLink: connectionActionURL != nil
                    )
                ) { action in
                    connectionActionControl(action, url: connectionActionURL)
                }
            }
        }
    }

    private var windowTitle: String {
        ConnectionWindowTitlePresentation.title(
            for: selection.connection,
            timeIsUnderTitle: timeIsUnderTitle
        )
    }

    private var connectionActionURL: URL? {
        selection.connection.shareURL.flatMap(AppLanguagePreference.localizedIDOSURL)
    }

    private var isPerformingExport: Bool {
        actionsModel.importingConnectionID == selection.connection.id ||
            actionsModel.exportingPDFConnectionID == selection.connection.id
    }

    /// Renders each connection action as an independent native toolbar control.
    @ViewBuilder
    private func connectionActionControl(
        _ action: ConnectionDetailToolbarAction,
        url: URL?
    ) -> some View {
        switch action {
        case .addToCalendar:
            Button {
                Task { await actionsModel.addToCalendar(selection.connection) }
            } label: {
                exportActionLabel(
                    action,
                    isPerforming: actionsModel.importingConnectionID == selection.connection.id
                )
            }
            .disabled(isPerformingExport)
            .accessibilityLabel(action.title)
            .help(action.title)
        case .saveAsPDF:
            Button {
                Task { await actionsModel.saveAsPDF(selection.connection) }
            } label: {
                exportActionLabel(
                    action,
                    isPerforming: actionsModel.exportingPDFConnectionID == selection.connection.id
                )
            }
            .disabled(isPerformingExport)
            .accessibilityLabel(action.title)
            .help(action.title)
        case .shareLink:
            if let url {
                ShareLink(item: url) {
                    connectionActionLabel(action)
                }
                .disabled(isPerformingExport)
                .help(action.title)
            }
        case .openInIDOS:
            if let url {
                Button {
                    openURL(url)
                } label: {
                    connectionActionLabel(action)
                }
                .disabled(isPerformingExport)
                .accessibilityLabel(action.title)
                .help(action.title)
            }
        }
    }

    @ViewBuilder
    private func exportActionLabel(
        _ action: ConnectionDetailToolbarAction,
        isPerforming: Bool
    ) -> some View {
        if isPerforming {
            ProgressView()
                .controlSize(.small)
        } else {
            connectionActionLabel(action)
        }
    }

    private func connectionActionLabel(_ action: ConnectionDetailToolbarAction) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .labelStyle(.iconOnly)
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
