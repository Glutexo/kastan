import AppKit
import Kastan
import SwiftUI

/// Chooses one mutually exclusive result body while a fresh search replaces the previous query.
enum ConnectionResultsPresentation: Equatable {
    case searching
    case empty
    case noResults
    case connections

    static func resolve(
        isSearching: Bool,
        hasCompletedSearch: Bool,
        hasConnections: Bool,
        hasError: Bool
    ) -> Self {
        if isSearching { return .searching }
        if hasConnections || hasError { return .connections }
        if hasCompletedSearch { return .noResults }
        return .empty
    }

    /// Mirrors the CLI by marking every displayed connection tied for the shortest parsed duration.
    static func shortestConnectionIDs(in connections: [IDOSConnection]) -> Set<String> {
        let comparableConnections = connections.compactMap { connection -> (id: String, minutes: Int)? in
            guard let minutes = durationInMinutes(connection.duration) else { return nil }
            return (connection.id, minutes)
        }
        guard let shortestDuration = comparableConnections.map(\.minutes).min() else { return [] }

        return Set(
            comparableConnections
                .filter { $0.minutes == shortestDuration }
                .map(\.id)
        )
    }

    /// Converts the localized duration units emitted by IDOS into one comparable minute value.
    private static func durationInMinutes(_ duration: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*([[:alpha:]]+)"#) else {
            return nil
        }

        let matches = expression.matches(
            in: duration,
            range: NSRange(duration.startIndex..<duration.endIndex, in: duration)
        )
        var total = 0
        var foundSupportedUnit = false

        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: duration),
                  let unitRange = Range(match.range(at: 2), in: duration),
                  let value = Int(duration[valueRange])
            else {
                continue
            }

            let unit = duration[unitRange].lowercased()
            if unit == "d" || unit.hasPrefix("day") {
                total += value * 24 * 60
                foundSupportedUnit = true
            } else if unit == "h" || unit.hasPrefix("hour") || unit.hasPrefix("hod") {
                total += value * 60
                foundSupportedUnit = true
            } else if unit == "m" || unit.hasPrefix("min") {
                total += value
                foundSupportedUnit = true
            }
        }

        return foundSupportedUnit ? total : nil
    }
}

/// Identifies a connection badge's stable symbol, passenger wording, and visual category.
enum ConnectionBadgeKind: Hashable {
    case direct
    case shortest

    var symbol: String {
        switch self {
        case .direct:
            "➡️"
        case .shortest:
            "⚡"
        }
    }

    var localizationKey: String {
        switch self {
        case .direct:
            "Direct"
        case .shortest:
            "Shortest"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .direct:
            .green.opacity(0.14)
        case .shortest:
            .yellow.opacity(0.18)
        }
    }

    func label(bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: localizationKey, value: localizationKey, table: nil)
    }

    func title(bundle: Bundle = .main) -> String {
        "\(symbol) \(label(bundle: bundle))"
    }
}

/// Defines the application-wide persisted choice for showing semantic badges on connections.
enum ConnectionBadgePreference {
    static let storageKey = "showsConnectionBadges"
    static let defaultValue = false
}

/// Builds semantic connection-result badges and filters them through the global View preference.
enum ConnectionBadgePresentation {
    /// Returns the badges allowed by the global View preference for one displayed connection.
    static func visibleKinds(
        showsBadges: Bool,
        isDirect: Bool,
        isShortest: Bool
    ) -> [ConnectionBadgeKind] {
        guard showsBadges else { return [] }

        var kinds: [ConnectionBadgeKind] = []
        if isDirect {
            kinds.append(.direct)
        }
        if isShortest {
            kinds.append(.shortest)
        }
        return kinds
    }

    static func direct(bundle: Bundle = .main) -> String {
        ConnectionBadgeKind.direct.title(bundle: bundle)
    }

    static func shortest(bundle: Bundle = .main) -> String {
        ConnectionBadgeKind.shortest.title(bundle: bundle)
    }
}

/// Shows a complete single-line badge when it fits and otherwise preserves only its semantic emoji.
struct AdaptiveConnectionBadge: View {
    let kind: ConnectionBadgeKind
    private let bundle: Bundle

    init(kind: ConnectionBadgeKind, bundle: Bundle = .main) {
        self.kind = kind
        self.bundle = bundle
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            badgeText(kind.title(bundle: bundle))
            badgeText(kind.symbol)
                .help(kind.label(bundle: bundle))
        }
        .accessibilityLabel(kind.label(bundle: bundle))
        .layoutPriority(-1)
    }

    private func badgeText(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind.backgroundColor, in: Capsule())
    }
}

/// Fits both route fields and their swap action exactly inside the padded search width.
enum ConnectionEndpointLayout {
    static let spacing: CGFloat = 10
    static let swapButtonWidth: CGFloat = 34

    static func fieldWidth(contentWidth: CGFloat) -> CGFloat {
        max((contentWidth - swapButtonWidth - (2 * spacing)) / 2, 0)
    }
}

/// Combines a compact macOS search workspace with expandable journey results.
struct ConnectionsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: ConnectionsViewModel
    let client: any IDOSClienting
    let showsConnectionBadges: Bool
    let showsItemDetails: Bool
    let showsServiceInformationText: Bool
    let showsStopNoteText: Bool
    @State private var isJourneyOptionsExpanded = false
    @State private var hasUsedDirectConnectionsShortcut = false
    @State private var isSearchFormCollapsed = false
    @State private var emailSelection: ConnectionSelection?
    @State private var optionIsPressed = SearchShortcutPresentation.isVisible(
        for: NSEvent.modifierFlags
    )

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
        .background {
            OptionModifierMonitor(isPressed: $optionIsPressed)
                .frame(width: 0, height: 0)
        }
        .focusedSceneValue(\.searchEditCommandContext, searchEditCommandContext)
        .sheet(item: $emailSelection) { selection in
            ConnectionEmailView(
                connection: selection.connection,
                timetable: selection.timetable,
                client: client
            )
        }
        .onAppear {
            model.refreshCurrentDateAndTime()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshCurrentDateAndTime()
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let errorMessage = model.errorMessage {
                HStack(spacing: 12) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if model.showsRefreshActionForError {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label("Refresh connections", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(!model.canSearch)
                        .help("Refresh connections")
                    }
                }
                    .foregroundStyle(.red)
                    .padding(12)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            results
        }
    }

    private func searchPanel(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            JourneySearchHeader(
                timetable: $model.timetable,
                date: $model.date,
                time: $model.time,
                isArrival: $model.isArrival,
                modeLabel: "Time means",
                departureLabel: "Departure",
                arrivalLabel: "Arrival",
                usesCurrentDateAndTime: model.usesCurrentDateAndTime,
                selectCurrentDateAndTime: {
                    model.selectCurrentDateAndTime()
                },
                showsCurrentDateAndTimeShortcut: optionIsPressed,
                usesCompactLayout: layout.usesStackedSearchControls
            )

            endpointControls(contentWidth: layout.contentWidth)

            if let endpointValidationMessage = model.endpointValidationMessage {
                Label(endpointValidationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
            }

            searchControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.1), value: model.endpointValidationMessage)
    }

    private func endpointControls(contentWidth: CGFloat) -> some View {
        let fieldWidth = ConnectionEndpointLayout.fieldWidth(contentWidth: contentWidth)

        return HStack(alignment: .placeInputCenter, spacing: ConnectionEndpointLayout.spacing) {
            fromField
                .frame(width: fieldWidth)
            swapButton
                .frame(width: ConnectionEndpointLayout.swapButtonWidth)
            toField
                .frame(width: fieldWidth)
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
            client: client,
            headerShortcutTitle: "Here",
            showsHeaderShortcut: optionIsPressed,
            isPerformingHeaderShortcut: model.locatingEndpoint == .from,
            isHeaderShortcutDisabled: model.locatingEndpoint != nil
        ) {
            Task { await model.fillCurrentLocation(in: .from) }
        }
    }

    private var toField: some View {
        PlaceAutocompleteField(
            title: "To",
            prompt: "Arrival place",
            text: $model.to,
            selection: $model.toSelection,
            timetable: model.timetable,
            scope: .places,
            client: client,
            headerShortcutTitle: "Here",
            showsHeaderShortcut: optionIsPressed,
            isPerformingHeaderShortcut: model.locatingEndpoint == .to,
            isHeaderShortcutDisabled: model.locatingEndpoint != nil
        ) {
            Task { await model.fillCurrentLocation(in: .to) }
        }
    }

    private var swapButton: some View {
        PlaceInputSwapButton(accessibilityLabel: "Swap departure and arrival") {
            model.swapEndpoints()
        }
    }

    private var searchControls: some View {
        JourneySearchControls(
            isSearching: model.isSearching,
            canSearch: model.canSearch,
            supplement: JourneySearchControlsSupplement(
                leading: journeyOptionsHeader,
                adjacent: directConnectionsOnlyShortcut,
                details: journeyOptionsDetails
            )
        ) {
            performSearch()
        }
    }

    /// Keeps the common direct-only shortcut synchronized with mutually exclusive transfer conditions.
    private var directConnectionsOnlyToggle: some View {
        Toggle("Direct connections only", isOn: Binding(
            get: { model.onlyDirect },
            set: {
                hasUsedDirectConnectionsShortcut = true
                model.setOnlyDirect($0)
            }
        ))
        .toggleStyle(.checkbox)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Reveals the direct-only shortcut for context and keeps it after its first explicit use.
    @ViewBuilder
    private var directConnectionsOnlyShortcut: some View {
        if DirectConnectionsShortcutPresentation.isVisible(
            journeyOptionsAreExpanded: isJourneyOptionsExpanded,
            optionIsPressed: optionIsPressed,
            hasBeenUsed: hasUsedDirectConnectionsShortcut
        ) {
            directConnectionsOnlyToggle
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

    private var searchEditCommandContext: SearchEditCommandContext {
        var enabledActions = FillCurrentAction.supportedActions(for: .connections)
        if model.locatingEndpoint != nil {
            enabledActions.subtract([.fromPlace, .toPlace])
        }
        return SearchEditCommandContext(
            enabledFillCurrentActions: enabledActions,
            performFillCurrent: fillCurrent,
            swapPlaces: swapPlaces
        )
    }

    /// Reveals the editable form before applying a current value from the application menu.
    private func fillCurrent(_ action: FillCurrentAction) {
        guard FillCurrentAction.supportedActions(for: .connections).contains(action) else { return }
        editSearch()

        switch action {
        case .fromPlace:
            guard model.locatingEndpoint == nil else { return }
            Task { await model.fillCurrentLocation(in: .from) }
        case .toPlace:
            guard model.locatingEndpoint == nil else { return }
            Task { await model.fillCurrentLocation(in: .to) }
        case .dateAndTime:
            model.selectCurrentDateAndTime()
        case .date:
            model.selectCurrentDate()
        case .time:
            model.selectCurrentTime()
        }
    }

    /// Reveals the editable form before swapping both connection endpoints from the Edit menu.
    private func swapPlaces() {
        editSearch()
        model.swapEndpoints()
    }

    private func performSearch() {
        guard model.canSearch else { return }
        model.refreshCurrentDateAndTime()
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

    /// Keeps the disclosure affordance on the shared action row while its content expands below it.
    private var journeyOptionsHeader: some View {
        JourneyOptionsDisclosureHeader(isExpanded: $isJourneyOptionsExpanded)
    }

    /// Uses the complete search width below the stable action row.
    @ViewBuilder
    private var journeyOptionsDetails: some View {
        if isJourneyOptionsExpanded {
            VStack(alignment: .leading, spacing: 0) {
                Divider()

                ForEach($model.journeyOptions) { $journeyOption in
                    journeyOptionRow(option: $journeyOption)
                        .padding(.vertical, 6)

                    Divider()
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    /// Sizes from every supported condition, with the native popup enforcing its compact-window cap.
    private func journeyOptionKindMenu(option: Binding<JourneyOptionEntry>) -> some View {
        JourneyOptionKindPicker(
            selection: journeyOptionKindBinding(for: option),
            availableKinds: model.availableJourneyOptionKinds(for: option.wrappedValue.id)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Lets the model restore remembered values whenever a transfer-related condition is selected again.
    private func journeyOptionKindBinding(for option: Binding<JourneyOptionEntry>) -> Binding<JourneyOptionKind> {
        let optionID = option.wrappedValue.id
        return Binding(
            get: {
                model.journeyOptions.first { $0.id == optionID }?.kind ?? .via
            },
            set: { model.setJourneyOptionKind($0, for: optionID) }
        )
    }

    @ViewBuilder
    private func journeyOptionValue(option: Binding<JourneyOptionEntry>) -> some View {
        switch option.wrappedValue.kind {
        case .via:
            PlaceAutocompleteField(
                prompt: "Via place",
                text: option.viaPlace,
                selection: option.viaSelection,
                timetable: model.timetable,
                scope: .places,
                client: client
            )
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
        case .minimumTransferTime:
            journeyDurationPicker(
                selection: option.minimumTransferTime,
                choices: JourneyDurationChoice.minimumTransferTimes,
                label: option.wrappedValue.kind.localizedTitle
            )
        case .maximumTransferTime:
            journeyDurationPicker(
                selection: option.maximumTransferTime,
                choices: JourneyDurationChoice.maximumTransferTimes,
                label: option.wrappedValue.kind.localizedTitle
            )
        case .maximumWalkingTime:
            journeyDurationPicker(
                selection: option.maximumWalkingTime,
                choices: JourneyDurationChoice.maximumWalkingTimes,
                label: option.wrappedValue.kind.localizedTitle
            )
        case .maximumCityWalkingTime:
            journeyDurationPicker(
                selection: option.maximumCityWalkingTime,
                choices: JourneyDurationChoice.maximumWalkingTimes,
                label: option.wrappedValue.kind.localizedTitle
            )
        case .walkToNearbyStops:
            journeyBooleanToggle(
                isOn: option.walkToNearbyStops,
                label: option.wrappedValue.kind.localizedTitle
            )
        case .sameNameWalkingTransfersOnly:
            journeyBooleanToggle(
                isOn: option.sameNameWalkingTransfersOnly,
                label: option.wrappedValue.kind.localizedTitle
            )
        }
    }

    /// Keeps the app's compact popup values aligned with the discrete durations accepted by IDOS.
    private func journeyDurationPicker(
        selection: Binding<Int>,
        choices: [JourneyDurationChoice],
        label: String
    ) -> some View {
        Picker(selection: selection) {
            ForEach(choices) { choice in
                Text(verbatim: choice.localizedTitle()).tag(choice.minutes)
            }
        } label: {
            Text(verbatim: label)
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(Text(verbatim: label))
    }

    /// Uses the same checkbox interaction as IDOS while the option name remains visible in the row picker.
    private func journeyBooleanToggle(isOn: Binding<Bool>, label: String) -> some View {
        Toggle(isOn: isOn) {
            Text(verbatim: label)
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(Text(verbatim: label))
    }

    /// Preserves the former stepper's accepted range while presenting the requested number field.
    private func maximumTransfersBinding(for option: Binding<JourneyOptionEntry>) -> Binding<Int> {
        let optionID = option.wrappedValue.id
        return Binding(
            get: {
                model.journeyOptions.first { $0.id == optionID }?.maximumTransfers ?? 0
            },
            set: { model.setMaximumTransfers($0, for: optionID) }
        )
    }

    @ViewBuilder
    private var results: some View {
        switch ConnectionResultsPresentation.resolve(
            isSearching: model.isSearching,
            hasCompletedSearch: model.hasCompletedSearch,
            hasConnections: !model.connections.isEmpty,
            hasError: model.errorMessage != nil
        ) {
        case .searching:
            ProgressView("Searching connections…")
                .frame(maxWidth: .infinity, minHeight: 180)
        case .empty:
            EmptyStateView(
                title: "No connections yet",
                systemImage: "arrow.left.arrow.right",
                description: "Enter a route and start a search."
            )
        case .noResults:
            EmptyStateView(
                title: "No connections found",
                systemImage: "magnifyingglass",
                description: "Try a different time, route, or timetable."
            )
        case .connections:
            let shortestConnectionIDs = ConnectionResultsPresentation.shortestConnectionIDs(
                in: model.connections
            )
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.connections.enumerated()), id: \.element.id) { index, connection in
                    let selection = ConnectionSelection(
                        connection: connection,
                        timetable: model.timetable
                    )
                    ConnectionCard(
                        number: index + 1,
                        connection: connection,
                        timetable: model.timetable,
                        client: client,
                        isShortest: shortestConnectionIDs.contains(connection.id),
                        showsConnectionBadges: showsConnectionBadges,
                        showsItemDetails: showsItemDetails,
                        showsServiceInformationText: showsServiceInformationText,
                        showsStopNoteText: showsStopNoteText,
                        isPerformingAction: model.processingEmailConnectionID == connection.id ||
                            model.processingCalendarConnectionID == connection.id ||
                            model.processingPDFConnectionID == connection.id,
                        showsActionMenu: true,
                        showsOpenConnectionButton: optionIsPressed,
                        timeFrameCoordinateSpace: nil,
                        openConnection: {
                            openWindow(
                                id: AppWindow.connectionDetail,
                                value: selection
                            )
                        },
                        openService: { openWindow(id: AppWindow.serviceDetail, value: $0) },
                        performEmailAction: { emailAction in
                            switch emailAction {
                            case .sendViaIDOS:
                                emailSelection = selection
                            case .composeInMail:
                                Task { await model.composeEmailInMail(for: connection) }
                            }
                        },
                        performCalendarAction: { calendarExportAction in
                            Task {
                                await model.performCalendarAction(
                                    calendarExportAction,
                                    for: connection
                                )
                            }
                        },
                        performPDFAction: { pdfExportAction in
                            Task {
                                await model.performPDFAction(
                                    pdfExportAction,
                                    for: connection
                                )
                            }
                        }
                    )
                }
            }
        }
    }
}

/// Expands journey conditions from either the native arrow or the full heading text.
struct JourneyOptionsDisclosureHeader: View {
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            EmptyView()
        } label: {
            Text("Journey options")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
        }
        .accessibilityLabel("Journey options")
        .frame(maxWidth: .infinity, alignment: .leading)
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
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
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

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView button: StableWidthPopUpButton,
        context: Context
    ) -> CGSize? {
        button.intrinsicContentSize
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

/// Uses the full catalog as a stable sizing reference without letting long localized titles overflow compact windows.
final class StableWidthPopUpButton: NSPopUpButton {
    static let maximumCatalogWidth: CGFloat = 200

    var sizingTitles: [String] = [] {
        didSet {
            guard sizingTitles != oldValue else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        let nativeSize = super.intrinsicContentSize
        guard !sizingTitles.isEmpty else {
            return nativeSize
        }

        let sizingButton = NSPopUpButton(frame: .zero, pullsDown: false)
        sizingButton.controlSize = controlSize
        sizingButton.bezelStyle = bezelStyle
        if let font {
            sizingButton.font = font
        }
        sizingButton.addItems(withTitles: sizingTitles)

        return NSSize(
            width: min(sizingButton.intrinsicContentSize.width, Self.maximumCatalogWidth),
            height: nativeSize.height
        )
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

/// Contains one complete journey and reveals its new-window header shortcut while Option is held.
struct ConnectionCard: View {
    let number: Int?
    let connection: IDOSConnection
    let timetable: IDOSTimetable
    let client: any IDOSClienting
    let isShortest: Bool
    let showsConnectionBadges: Bool
    let showsItemDetails: Bool
    let showsServiceInformationText: Bool
    let showsStopNoteText: Bool
    let isPerformingAction: Bool
    let showsActionMenu: Bool
    let showsOpenConnectionButton: Bool
    let timeFrameCoordinateSpace: String?
    let openConnection: (() -> Void)?
    let openService: (ServiceSelection) -> Void
    let performEmailAction: (ConnectionEmailAction) -> Void
    let performCalendarAction: (CalendarExportAction) -> Void
    let performPDFAction: (PDFExportAction) -> Void

    @ViewBuilder
    var body: some View {
        if showsActionMenu, let openConnection {
            cardContent
                .contentShape(Rectangle())
                .contextMenu {
                    actionMenuContent(openInNewWindow: openConnection)
                }
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if let number {
                            Text(AppLocalization.string("Connection %lld", number))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text("\(connection.departureTime) → \(connection.arrivalTime)")
                            .font(.title2.bold().monospacedDigit())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(2)
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
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        ForEach(
                            ConnectionBadgePresentation.visibleKinds(
                                showsBadges: showsConnectionBadges,
                                isDirect: connection.legs.count <= 1,
                                isShortest: isShortest
                            ),
                            id: \.self
                        ) { kind in
                            AdaptiveConnectionBadge(kind: kind)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        openConnection?()
                    }
                    if showsOpenConnectionButton, let openConnection {
                        Button(action: openConnection) {
                            Label("Open connection in new window", systemImage: "macwindow")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Open connection in new window")
                    }
                    if showsActionMenu, let openConnection {
                        Menu {
                            actionMenuContent(openInNewWindow: openConnection)
                        } label: {
                            if isPerformingAction {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                        .menuStyle(.borderlessButton)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    openConnection?()
                }

                if !connection.legs.isEmpty {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(Array(connection.legs.enumerated()), id: \.offset) { index, leg in
                            ConnectionLegRow(
                                leg: leg,
                                client: client,
                                showsItemDetails: showsItemDetails,
                                showsServiceInformationText: showsServiceInformationText,
                                showsStopNoteText: showsStopNoteText,
                                openService: openService
                            )
                            .alternatingRowBackground(at: index)
                            .id("\(index):\(leg.id ?? "unavailable")")
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

    private var connectionActionURL: URL? {
        connection.shareURL.flatMap(AppLanguagePreference.localizedIDOSURL)
    }

    private var connectionShareText: String {
        CLIPlainTextPresentation().connection(connection, timetable: timetable)
    }

    private func actionMenuContent(openInNewWindow: @escaping () -> Void) -> some View {
        ConnectionContextMenuContent(
            permanentLink: connectionActionURL,
            shareText: connectionShareText,
            isPerformingAction: isPerformingAction,
            openInNewWindow: openInNewWindow,
            performEmailAction: performEmailAction,
            performCalendarAction: performCalendarAction,
            performPDFAction: performPDFAction
        )
    }
}

/// Shows one complete connection in its own window with result actions in the native toolbar.
struct ConnectionDetailView: View {
    /// Keeps the adaptive journey card usable at the narrowest supported detail-window size.
    static let minimumWindowWidth: CGFloat = 400
    /// Opens complete connections directly in their compact supported layout.
    static let defaultWindowWidth = minimumWindowWidth

    private static let scrollCoordinateSpace = "connection-detail-scroll"

    @Environment(\.openWindow) private var openWindow
    @StateObject private var actionsModel: ConnectionsViewModel
    @State private var timeIsUnderTitle = false
    @State private var isEmailPresented = false
    private let selection: ConnectionSelection
    private let client: any IDOSClienting
    private let showsConnectionBadges: Bool
    private let showsItemDetails: Bool
    private let showsServiceInformationText: Bool
    private let showsStopNoteText: Bool

    init(
        selection: ConnectionSelection,
        client: any IDOSClienting,
        showsConnectionBadges: Bool,
        showsItemDetails: Bool,
        showsServiceInformationText: Bool,
        showsStopNoteText: Bool
    ) {
        self.selection = selection
        self.client = client
        self.showsConnectionBadges = showsConnectionBadges
        self.showsItemDetails = showsItemDetails
        self.showsServiceInformationText = showsServiceInformationText
        self.showsStopNoteText = showsStopNoteText
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
                    timetable: selection.timetable,
                    client: client,
                    isShortest: false,
                    showsConnectionBadges: showsConnectionBadges,
                    showsItemDetails: showsItemDetails,
                    showsServiceInformationText: showsServiceInformationText,
                    showsStopNoteText: showsStopNoteText,
                    isPerformingAction: isPerformingAction,
                    showsActionMenu: false,
                    showsOpenConnectionButton: false,
                    timeFrameCoordinateSpace: Self.scrollCoordinateSpace,
                    openConnection: nil,
                    openService: { openWindow(id: AppWindow.serviceDetail, value: $0) },
                    performEmailAction: performEmailAction,
                    performCalendarAction: { calendarExportAction in
                        Task {
                            await actionsModel.performCalendarAction(
                                calendarExportAction,
                                for: selection.connection
                            )
                        }
                    },
                    performPDFAction: { pdfExportAction in
                        Task {
                            await actionsModel.performPDFAction(
                                pdfExportAction,
                                for: selection.connection
                            )
                        }
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
        .frame(
            minWidth: Self.minimumWindowWidth,
            minHeight: 420
        )
        .navigationTitle(windowTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(
                    ResultDetailAction.availableActions(
                        hasPermanentLink: connectionActionURL != nil,
                        canSendByEmail: true
                    )
                ) { action in
                    connectionActionControl(action, url: connectionActionURL)
                }
            }
        }
        .focusedSceneValue(\.resultDetailCommandContext, resultDetailCommandContext)
        .sheet(isPresented: $isEmailPresented) {
            ConnectionEmailView(
                connection: selection.connection,
                timetable: selection.timetable,
                client: client
            )
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

    private var connectionShareText: String {
        CLIPlainTextPresentation().connection(
            selection.connection,
            timetable: selection.timetable
        )
    }

    private var isPerformingAction: Bool {
        actionsModel.processingEmailConnectionID == selection.connection.id ||
            actionsModel.processingCalendarConnectionID == selection.connection.id ||
            actionsModel.processingPDFConnectionID == selection.connection.id
    }

    private func performEmailAction(_ action: ConnectionEmailAction) {
        switch action {
        case .sendViaIDOS:
            isEmailPresented = true
        case .composeInMail:
            Task { await actionsModel.composeEmailInMail(for: selection.connection) }
        }
    }

    private var resultDetailCommandContext: ResultDetailCommandContext {
        ResultDetailCommandContext(
            hasLoadedResult: true,
            isPerformingAction: isPerformingAction,
            permanentLink: connectionActionURL,
            shareText: connectionShareText,
            performEmailAction: performEmailAction,
            performCalendarAction: { calendarExportAction in
                Task {
                    await actionsModel.performCalendarAction(
                        calendarExportAction,
                        for: selection.connection
                    )
                }
            },
            performPDFAction: { pdfExportAction in
                Task {
                    await actionsModel.performPDFAction(
                        pdfExportAction,
                        for: selection.connection
                    )
                }
            }
        )
    }

    /// Renders each connection action as an independent native toolbar control.
    @ViewBuilder
    private func connectionActionControl(
        _ action: ResultDetailAction,
        url: URL?
    ) -> some View {
        switch action {
        case .sendByEmail:
            ConnectionEmailButton(
                placement: .toolbar,
                perform: performEmailAction
            ) { emailAction in
                emailActionLabel(
                    action,
                    emailAction: emailAction,
                    isPerforming: actionsModel.processingEmailConnectionID == selection.connection.id
                )
            }
            .disabled(isPerformingAction || url == nil)
        case .addToCalendar:
            CalendarExportButton(placement: .toolbar) { calendarExportAction in
                Task {
                    await actionsModel.performCalendarAction(
                        calendarExportAction,
                        for: selection.connection
                    )
                }
            } label: { calendarExportAction in
                exportActionLabel(
                    action,
                    calendarExportAction: calendarExportAction,
                    isPerforming: actionsModel.processingCalendarConnectionID == selection.connection.id
                )
            }
            .disabled(isPerformingAction)
        case .openPDF:
            PDFExportButton(placement: .toolbar) { pdfExportAction in
                Task {
                    await actionsModel.performPDFAction(
                        pdfExportAction,
                        for: selection.connection
                    )
                }
            } label: { pdfExportAction in
                exportActionLabel(
                    action,
                    pdfExportAction: pdfExportAction,
                    isPerforming: actionsModel.processingPDFConnectionID == selection.connection.id
                )
            }
            .disabled(isPerformingAction)
        case .share:
            ResultShareButton(
                link: url,
                text: connectionShareText,
                placement: .toolbar
            ) { sharingAction in
                connectionActionLabel(action, sharingAction: sharingAction)
            }
            .disabled(isPerformingAction)
        }
    }

    @ViewBuilder
    private func emailActionLabel(
        _ action: ResultDetailAction,
        emailAction: ConnectionEmailAction,
        isPerforming: Bool
    ) -> some View {
        if isPerforming {
            ProgressView()
                .controlSize(.small)
        } else {
            connectionActionLabel(action, emailAction: emailAction)
        }
    }

    @ViewBuilder
    private func exportActionLabel(
        _ action: ResultDetailAction,
        calendarExportAction: CalendarExportAction = .addToCalendar,
        pdfExportAction: PDFExportAction = .openInPreview,
        isPerforming: Bool
    ) -> some View {
        if isPerforming {
            ProgressView()
                .controlSize(.small)
        } else {
            connectionActionLabel(
                action,
                calendarExportAction: calendarExportAction,
                pdfExportAction: pdfExportAction
            )
        }
    }

    private func connectionActionLabel(
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
            .labelStyle(.iconOnly)
    }
}

private struct ConnectionLegRow: View {
    let leg: IDOSConnectionLeg
    let client: any IDOSClienting
    let showsItemDetails: Bool
    let showsServiceInformationText: Bool
    let showsStopNoteText: Bool
    let openService: (ServiceSelection) -> Void
    @StateObject private var contextMenuModel: ServiceDetailViewModel
    @State private var suppressesPrimaryAction = false
    @State private var isPreviewPresented = false

    init(
        leg: IDOSConnectionLeg,
        client: any IDOSClienting,
        showsItemDetails: Bool,
        showsServiceInformationText: Bool,
        showsStopNoteText: Bool,
        openService: @escaping (ServiceSelection) -> Void
    ) {
        self.leg = leg
        self.client = client
        self.showsItemDetails = showsItemDetails
        self.showsServiceInformationText = showsServiceInformationText
        self.showsStopNoteText = showsStopNoteText
        self.openService = openService
        _contextMenuModel = StateObject(
            wrappedValue: ServiceDetailViewModel(id: leg.id ?? "", client: client)
        )
    }

    @ViewBuilder
    var body: some View {
        if let selection {
            rowButton(selection: selection)
                .contextMenu {
                    ServiceContextMenuContent(
                        model: contextMenuModel,
                        showPreview: { isPreviewPresented = true },
                        openInNewWindow: { openService(selection) }
                    )
                }
        } else {
            rowButton(selection: nil)
                .disabled(true)
        }
    }

    private var selection: ServiceSelection? {
        leg.id.map {
            ServiceSelection(
                id: $0,
                highlight: ServiceRouteHighlight(
                    fromStop: leg.fromStation,
                    toStop: leg.toStation
                )
            )
        }
    }

    private func rowButton(selection: ServiceSelection?) -> some View {
        Button {
            guard !suppressesPrimaryAction else {
                suppressesPrimaryAction = false
                return
            }
            if let selection {
                openService(selection)
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
                        if !showsServiceInformationText {
                            ServiceInformationSummary(
                                values: leg.serviceInformation,
                                showsText: false
                            )
                        }
                        if let platform = ResultMetadata.compactConnectionPlatform(leg) {
                            CompactStopMetadata(values: [platform])
                        }
                        Spacer()
                        if leg.id != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if showsServiceInformationText {
                        ServiceInformationSummary(
                            values: leg.serviceInformation,
                            showsText: true
                        )
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
                    if let metadata = ResultMetadata.connectionLeg(
                        leg,
                        showsDetails: showsItemDetails
                    ) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            .forceClickPreview(
                size: ResultPreviewLayout.serviceSize,
                isEnabled: selection != nil,
                suppressesPrimaryAction: $suppressesPrimaryAction,
                isPresented: $isPreviewPresented
            ) {
                if let selection {
                    ServiceDetailView(
                        selection: selection,
                        client: client,
                        showsItemDetails: showsItemDetails,
                        showsStopNoteText: showsStopNoteText,
                        presentation: .preview
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }
}
