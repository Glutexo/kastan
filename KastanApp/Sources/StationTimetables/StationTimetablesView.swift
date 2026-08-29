import AppKit
import Foundation
import Kastan
import SwiftUI

/// Searches and presents IDOS station timetables for MHD and integrated transport systems.
struct StationTimetablesView: View {
    @ObservedObject var model: StationTimetablesViewModel
    let client: any IDOSClienting
    let showsItemDetails: Bool
    let showsStopNoteText: Bool
    @State private var isSearchFormCollapsed = false
    @State private var isNotesExpanded = false
    @State private var isExplanationsExpanded = false
    @State private var selectedResultSection = StationTimetableResultSection.stops

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailLayout(availableWidth: geometry.size.width)

            SearchWorkspace(
                layout: layout,
                searchVerticalPadding: isSearchFormCollapsed ? 10 : 18
            ) {
                if isSearchFormCollapsed {
                    SearchSummaryBar(
                        summary: searchSummary,
                        systemImage: "calendar",
                        edit: editSearch
                    )
                    .transition(.opacity)
                } else {
                    searchPanel(usesCompactLayout: layout.usesStackedSearchControls)
                        .transition(.opacity)
                }
            } resultsContent: {
                resultsPanel(layout: layout)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .animation(.easeInOut(duration: 0.18), value: isSearchFormCollapsed)
        }
        .focusedSceneValue(\.searchEditCommandContext, searchEditCommandContext)
    }

    private func resultsPanel(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            results(availableWidth: layout.contentWidth)
        }
    }

    private func searchPanel(usesCompactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.municipalities.isEmpty {
                StationTimetableSearchHeader(
                    timetable: timetableBinding,
                    date: $model.date,
                    wholeWeek: $model.wholeWeek,
                    usesCompactLayout: usesCompactLayout
                )

                standardRouteFields
            } else {
                odisContextFields(usesCompactLayout: usesCompactLayout)
                directionFields
            }

            HStack(alignment: .center, spacing: 12) {
                Spacer(minLength: 0)
                searchButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standardRouteFields: some View {
        ViewThatFits(in: .horizontal) {
            allRouteFields
            VStack(alignment: .leading, spacing: 12) {
                lineField
                directionFields
            }
        }
    }

    private func odisContextFields(usesCompactLayout: Bool) -> some View {
        let horizontalSpacing: CGFloat = usesCompactLayout ? 8 : 12

        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 14) {
            GridRow(alignment: .bottom) {
                SearchTimetablePicker(
                    timetable: timetableBinding,
                    allowedTimetables: AppTimetableGroup.stationTimetables,
                    usesCompactLayout: usesCompactLayout
                )
                Spacer(minLength: horizontalSpacing)
                    .gridCellUnsizedAxes(.vertical)
                StationTimetableDateSearchControl(
                    date: $model.date,
                    wholeWeek: $model.wholeWeek
                )
            }

            GridRow(alignment: .bottom) {
                StationTimetableMunicipalityPicker(
                    municipality: municipalityBinding,
                    municipalities: model.municipalities
                )
                Spacer(minLength: horizontalSpacing)
                    .gridCellUnsizedAxes(.vertical)
                lineField
                    .frame(width: SearchDatePickerLayout.buttonWidth)
                    .gridCellUnsizedAxes(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allRouteFields: some View {
        HStack(alignment: .placeInputCenter, spacing: 12) {
            lineField
            fromField
            swapButton
            toField
        }
    }

    private var directionFields: some View {
        HStack(alignment: .placeInputCenter, spacing: 12) {
            fromField
            swapButton
            toField
        }
    }

    private var lineField: some View {
        PlaceAutocompleteField(
            title: "Line",
            prompt: "Line number or name",
            text: $model.line,
            timetable: model.timetable,
            scope: .stationTimetableLines,
            stationTimetableMunicipality: model.municipality,
            client: client,
            onSelection: model.selectLineSuggestion
        )
        .frame(minWidth: 170, maxWidth: .infinity)
    }

    private var fromField: some View {
        PlaceAutocompleteField(
            title: "From",
            prompt: "Direction from",
            text: $model.from,
            timetable: model.timetable,
            scope: .stationTimetableStops,
            stationTimetableLine: model.line,
            stationTimetableMunicipality: model.municipality,
            client: client
        )
        .frame(minWidth: 180, maxWidth: .infinity)
    }

    private var toField: some View {
        PlaceAutocompleteField(
            title: "To",
            prompt: "Direction to",
            text: $model.to,
            timetable: model.timetable,
            scope: .stationTimetableStops,
            stationTimetableLine: model.line,
            stationTimetableMunicipality: model.municipality,
            client: client
        )
        .frame(minWidth: 180, maxWidth: .infinity)
    }

    private var swapButton: some View {
        PlaceInputSwapButton(accessibilityLabel: "Swap direction stops") {
            model.swapDirectionStops()
        }
    }

    private var searchButton: some View {
        SearchActionButton(
            isSearching: model.isSearching,
            canSearch: model.canSearch,
            action: performSearch
        )
    }

    private var searchSummary: SearchSummaryPresentation {
        var details = [
            model.timetable.appDisplayName,
        ]
        if let municipality = model.municipality {
            details.append(municipality.name)
        }
        details.append(IDOSRequestFormatting.date(from: model.date))
        if model.wholeWeek {
            details.append(AppLocalization.string("Whole week"))
        }
        return SearchSummaryPresentation(
            title: "\(model.line): \(model.from) → \(model.to)",
            details: details
        )
    }

    private var timetableBinding: Binding<IDOSTimetable> {
        Binding(
            get: { model.timetable },
            set: { timetable in model.selectTimetable(slug: timetable.slug) }
        )
    }

    private var municipalityBinding: Binding<IDOSStationTimetableMunicipality?> {
        Binding(
            get: { model.municipality },
            set: { municipality in
                if let municipality {
                    model.selectMunicipality(municipality)
                }
            }
        )
    }

    private var searchEditCommandContext: SearchEditCommandContext {
        SearchEditCommandContext(
            enabledFillCurrentActions: FillCurrentAction.supportedActions(for: .stationTimetables),
            performFillCurrent: fillCurrent,
            swapPlaces: swapPlaces
        )
    }

    /// Reveals the editable form before applying today's date from the application menu.
    private func fillCurrent(_ action: FillCurrentAction) {
        guard FillCurrentAction.supportedActions(for: .stationTimetables).contains(action) else { return }
        editSearch()

        switch action {
        case .date:
            model.selectCurrentDate()
        case .fromPlace, .toPlace, .dateAndTime, .time:
            break
        }
    }

    /// Reveals the editable form before swapping both direction stops from the Edit menu.
    private func swapPlaces() {
        editSearch()
        model.swapDirectionStops()
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

    @ViewBuilder
    private func results(availableWidth: CGFloat) -> some View {
        if model.isSearching, model.result == nil {
            ProgressView("Loading station timetable…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if let result = model.result {
            stationTimetable(result, availableWidth: availableWidth)
        } else if model.errorMessage == nil {
            EmptyStateView(
                title: "No station timetable yet",
                systemImage: "calendar",
                description: "Choose an MHD line and direction, then start a search."
            )
        }
    }

    private func stationTimetable(
        _ result: IDOSStationTimetable,
        availableWidth: CGFloat
    ) -> some View {
        let layout = StationTimetableResultLayout(availableWidth: availableWidth)

        return VStack(alignment: .leading, spacing: 18) {
            resultHeader(result, showsSectionPicker: layout.usesSectionPicker)

            if layout.usesSectionPicker {
                compactResultSection(result)
            } else {
                HStack(alignment: .top, spacing: StationTimetableResultLayout.columnSpacing) {
                    stops(result)
                        .frame(width: layout.columnWidth, alignment: .topLeading)
                    schedules(result)
                        .frame(width: layout.columnWidth, alignment: .topLeading)
                }
            }

            if !result.notes.isEmpty {
                StationTimetableRemarksDisclosure(
                    title: "Notes",
                    systemImage: "info.circle",
                    values: result.notes,
                    calendarContext: result.notes + result.explanations,
                    isExpanded: $isNotesExpanded
                )
            }
        }
    }

    @ViewBuilder
    private func compactResultSection(_ result: IDOSStationTimetable) -> some View {
        switch selectedResultSection {
        case .stops:
            stops(result)
        case .timetable:
            schedules(result)
        }
    }

    private func resultHeader(
        _ result: IDOSStationTimetable,
        showsSectionPicker: Bool
    ) -> some View {
        let title: String
        if let transportMode = result.transportMode {
            title = "\(transportMode.emoji) \(result.lineName)"
        } else {
            title = result.lineName
        }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                StationTimetableRouteHeading(
                    lineTitle: title,
                    route: "\(result.fromStop) → \(result.toStop)",
                    isLockout: result.isLockout
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await model.reverseDirection() }
                } label: {
                    Label("Reverse direction", systemImage: "arrow.triangle.swap")
                }
                .buttonStyle(.bordered)
                .disabled(model.isSearching)

                if let value = result.shareURL,
                   let url = AppLanguagePreference.localizedIDOSURL(from: value)
                {
                    ResultShareButton(
                        link: url,
                        text: nil,
                        placement: .toolbar,
                        offersTextAlternate: false
                    ) { _ in
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share Link")
                    .help("Share Link")
                }
            }

            if showsSectionPicker {
                StationTimetableResultSectionPicker(selection: $selectedResultSection)
            }
        }
    }

    private func stops(_ result: IDOSStationTimetable) -> some View {
        let selectedStopIndex = result.stops.firstIndex(where: \.isSelected)

        return VStack(alignment: .leading, spacing: 8) {
            Label("Stops", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(result.stops.enumerated()), id: \.offset) { index, stop in
                    let notePresentation = StopNotePresentation(
                        notes: stop.notes,
                        showsText: showsStopNoteText
                    )
                    let compactMetadata = ResultMetadata.compactStopValues(
                        showsDetails: showsItemDetails,
                        showsSymbolsAsText: showsStopNoteText,
                        ResultMetadata.compactStationTimetable(
                            tariffZone: stop.tariffZone,
                            platform: stop.platform
                        )
                    )
                    let timelinePresentation = StationTimetableStopTimelinePresentation(
                        index: index,
                        stopCount: result.stops.count,
                        selectedStopIndex: selectedStopIndex
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            Task { await model.selectStop(at: index) }
                        } label: {
                            HStack(
                                alignment: .top,
                                spacing: StationTimetableStopTimelineLayout.columnSpacing
                            ) {
                                Text(minuteOffsetText(stop.minuteOffset))
                                    .font(.callout.bold().monospacedDigit())
                                    .foregroundStyle(stop.isSelected ? Color.accentColor : Color.secondary)
                                    .frame(
                                        width: StationTimetableStopTimelineLayout.minuteWidth,
                                        alignment: .trailing
                                    )
                                Color.clear
                                    .frame(
                                        width: RouteStopMarker.diameter,
                                        height: RouteStopMarker.diameter
                                    )
                                    .padding(
                                        .top,
                                        StationTimetableStopTimelineLayout.markerTopPadding
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(stop.name)
                                        StopNoteSymbols(values: notePresentation.symbols)
                                        CompactStopMetadata(values: compactMetadata)
                                    }
                                    .fontWeight(stop.isSelected ? .semibold : .regular)
                                    .foregroundStyle(.primary)
                                    if let metadata = ResultMetadata.visible(
                                        showsDetails: showsItemDetails && showsStopNoteText,
                                        stopMetadata(stop)
                                    ) {
                                        Text(metadata)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(
                                .horizontal,
                                StationTimetableStopTimelineLayout.rowHorizontalPadding
                            )
                            .padding(.top, StationTimetableStopTimelineLayout.rowTopPadding)
                            .padding(.bottom, notePresentation.textNotes.isEmpty ? 6 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(StationTimetableStopButtonStyle())
                        .disabled(stop.isSelected || model.isSearching)

                        if !notePresentation.textNotes.isEmpty {
                            NoteText(notePresentation.textNotes.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(
                                    .leading,
                                    StationTimetableStopTimelineLayout.textLeadingPadding
                                )
                                .padding(.trailing, 8)
                                .padding(.bottom, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        stop.isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .alternatingRowBackground(at: index)
                    .overlay {
                        StationTimetableStopTimeline(
                            presentation: timelinePresentation
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func schedules(_ result: IDOSStationTimetable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedStop = result.selectedStop {
                Label(selectedStop.name, systemImage: "clock")
                    .font(.headline)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(result.schedules.enumerated()), id: \.offset) { _, schedule in
                        scheduleTable(schedule, explanations: result.explanations)
                            .frame(minWidth: 260, maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(result.schedules.enumerated()), id: \.offset) { _, schedule in
                            scheduleTable(schedule, explanations: result.explanations)
                                .frame(width: 260)
                        }
                    }
                }
            }

            if !result.explanations.isEmpty {
                StationTimetableRemarksDisclosure(
                    title: "Explanations",
                    systemImage: "questionmark.circle",
                    values: result.explanations,
                    calendarContext: result.notes + result.explanations,
                    isExpanded: $isExplanationsExpanded
                )
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduleTable(
        _ schedule: IDOSStationTimetableSchedule,
        explanations: [String]
    ) -> some View {
        GroupBox(StationTimetableScheduleLabelPresentation.title(schedule.label)) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(schedule.hours.enumerated()), id: \.offset) { index, hour in
                    HStack(alignment: .top, spacing: 12) {
                        Text(hour.hour)
                            .font(.body.bold().monospacedDigit())
                            .frame(width: 28, alignment: .trailing)
                        if hour.departures.isEmpty {
                            Text("—")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        } else {
                            StationTimetableDepartureTimes(
                                values: hour.departures,
                                explanations: explanations
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alternatingRowBackground(at: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func minuteOffsetText(_ value: Int?) -> String {
        guard let value else { return "–" }
        return String(value)
    }

    /// Keeps fare zones and the IDOS platform or stand number together with their route stop.
    private func stopMetadata(_ stop: IDOSStationTimetableStop) -> String? {
        let values = [
            stop.tariffZone.map { AppLocalization.string("Zone %@", $0) },
            stop.platform.map { AppLocalization.string("Station timetable platform %@", $0) },
        ].compactMap(\.self)
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

/// Separates an IDOS minute from its appended marker and associates the marker with the
/// matching timetable explanation shown on hover.
struct StationTimetableDeparturePresentation: Equatable {
    let minute: String
    let marker: String?
    let explanation: String?

    init(value: String, explanations: [String]) {
        let markerStart = value.firstIndex { !$0.isNumber } ?? value.endIndex
        let parsedMinute = String(value[..<markerStart])
        let parsedMarker = String(value[markerStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !parsedMinute.isEmpty, !parsedMarker.isEmpty else {
            minute = value
            marker = nil
            explanation = nil
            return
        }

        minute = parsedMinute
        marker = parsedMarker
        let matchingExplanations = explanations.filter { value in
            guard let separator = value.firstIndex(of: ":") else { return false }
            let key = value[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            return !key.isEmpty && parsedMarker.contains(key)
        }
        explanation = matchingExplanations.isEmpty
            ? nil
            : matchingExplanations.joined(separator: "\n")
    }
}

/// Presents minute markers as secondary information attached to their departure while keeping
/// each departure together when a busy hour wraps onto another line.
struct StationTimetableDepartureTimes: View {
    let values: [String]
    let explanations: [String]

    var body: some View {
        StationTimetableDepartureFlowLayout(
            horizontalSpacing: StationTimetableDepartureLayout.columnSpacing,
            verticalSpacing: StationTimetableDepartureLayout.rowSpacing
        ) {
            ForEach(Array(presentations.enumerated()), id: \.offset) { _, presentation in
                StationTimetableDepartureTime(presentation: presentation)
                    .frame(
                        width: StationTimetableDepartureLayout.columnWidth,
                        alignment: .leading
                    )
            }
        }
    }

    var presentations: [StationTimetableDeparturePresentation] {
        values.map {
            StationTimetableDeparturePresentation(value: $0, explanations: explanations)
        }
    }
}

/// Keeps timetable minutes in stable columns while leaving room for their attached IDOS markers.
enum StationTimetableDepartureLayout {
    static let columnWidth: CGFloat = 40
    static let columnSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 2
}

/// Keeps the primary minute prominent and exposes the complete IDOS explanation from its smaller
/// marker to pointer and accessibility users.
private struct StationTimetableDepartureTime: View {
    let presentation: StationTimetableDeparturePresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: presentation.minute)
                .font(.body.monospacedDigit())
            marker
        }
        .fixedSize()
    }

    @ViewBuilder
    private var marker: some View {
        if let value = presentation.marker {
            if let explanation = presentation.explanation {
                markerLabel(value)
                    .help(Text(verbatim: explanation))
                    .accessibilityLabel(Text(verbatim: explanation))
            } else {
                markerLabel(value)
            }
        }
    }

    private func markerLabel(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .baselineOffset(2)
    }
}

/// Wraps complete departure tokens without separating a minute from its explanatory marker.
struct StationTimetableDepartureFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrangement(for: subviews, availableWidth: finiteWidth(proposal.width)).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrangement(for: subviews, availableWidth: finiteWidth(bounds.width))
        for (index, position) in arrangement.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private struct Arrangement {
        let size: CGSize
        let positions: [CGPoint]
    }

    private func arrangement(
        for subviews: Subviews,
        availableWidth: CGFloat
    ) -> Arrangement {
        guard !subviews.isEmpty else {
            return Arrangement(size: .zero, positions: [])
        }

        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            contentWidth = max(contentWidth, x + size.width)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return Arrangement(
            size: CGSize(width: min(contentWidth, availableWidth), height: y + rowHeight),
            positions: positions
        )
    }

    private func finiteWidth(_ proposedWidth: CGFloat?) -> CGFloat {
        guard let proposedWidth, proposedWidth.isFinite else {
            return .greatestFiniteMagnitude
        }
        return max(proposedWidth, 0)
    }
}

/// Keeps an IDOS schedule date intact while presenting its following weekday as inline prose.
enum StationTimetableScheduleLabelPresentation {
    static func title(
        _ value: String,
        locale: Locale = AppLocalization.locale(for: .main)
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale

        for weekday in formatter.weekdaySymbols ?? [] {
            guard let range = value.range(
                of: weekday,
                options: [.caseInsensitive, .anchored, .backwards],
                locale: locale
            ) else {
                continue
            }
            if range.lowerBound > value.startIndex {
                let precedingIndex = value.index(before: range.lowerBound)
                guard !value[precedingIndex].isLetter else { continue }
            }
            return String(value[..<range.lowerBound]) + weekday
        }

        return value
    }
}

/// Identifies the route or schedule content selected in a compact station-timetable result.
enum StationTimetableResultSection: Hashable {
    case stops
    case timetable
}

/// Gives both result columns equal space until either would become too narrow to read.
struct StationTimetableResultLayout {
    static let columnSpacing: CGFloat = 18
    static let minimumColumnWidth: CGFloat = 280

    let availableWidth: CGFloat

    var columnWidth: CGFloat {
        max((availableWidth - Self.columnSpacing) / 2, 0)
    }

    var usesSectionPicker: Bool {
        columnWidth < Self.minimumColumnWidth
    }
}

/// Switches between route stops and the selected stop's timetable without stacking compact results.
struct StationTimetableResultSectionPicker: View {
    @Binding var selection: StationTimetableResultSection

    var body: some View {
        Picker("Station timetable content", selection: $selection) {
            Text("Stops").tag(StationTimetableResultSection.stops)
            Text("Timetable").tag(StationTimetableResultSection.timetable)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Keeps the selected stop's primary and secondary information colors intact while its disabled
/// button state prevents a redundant timetable reload.
struct StationTimetableStopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Keeps every station-timetable marker and connector on the same stable row coordinates.
enum StationTimetableStopTimelineLayout {
    static let rowHorizontalPadding: CGFloat = 8
    static let rowTopPadding: CGFloat = 6
    static let minuteWidth: CGFloat = 28
    static let columnSpacing: CGFloat = 10
    static let markerTopPadding: CGFloat = 2

    static var markerCenterX: CGFloat {
        rowHorizontalPadding + minuteWidth + columnSpacing + (RouteStopMarker.diameter / 2)
    }

    /// Aligns a stop's expanded note text with the name and optional metadata above it.
    static var textLeadingPadding: CGFloat {
        markerCenterX + (RouteStopMarker.diameter / 2) + columnSpacing
    }

    static var markerCenterY: CGFloat {
        rowTopPadding + markerTopPadding + (RouteStopMarker.diameter / 2)
    }
}

/// Describes the same route highlight used by a complete service, starting at the selected stop.
struct StationTimetableStopTimelinePresentation: Equatable {
    let isFirst: Bool
    let isLast: Bool
    let markerIsHighlighted: Bool
    let markerIsEmphasized: Bool
    let showsMarkerCenter: Bool
    let topConnectorIsHighlighted: Bool
    let bottomConnectorIsHighlighted: Bool

    init(index: Int, stopCount: Int, selectedStopIndex: Int?) {
        isFirst = index == 0
        isLast = index == stopCount - 1
        markerIsHighlighted = selectedStopIndex.map { index >= $0 } ?? false
        markerIsEmphasized = index == selectedStopIndex
        showsMarkerCenter = isFirst || isLast || markerIsEmphasized
        topConnectorIsHighlighted =
            !isFirst && (selectedStopIndex.map { index > $0 } ?? false)
        bottomConnectorIsHighlighted =
            !isLast && (selectedStopIndex.map { index >= $0 } ?? false)
    }
}

/// Draws one full-height route segment without taking interaction away from its stop row.
struct StationTimetableStopTimeline: View {
    let presentation: StationTimetableStopTimelinePresentation

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(presentation.isFirst ? Color.clear : topConnectorColor)
                    .frame(
                        width: 2,
                        height: StationTimetableStopTimelineLayout.markerCenterY
                    )
                    .offset(x: connectorX)

                Rectangle()
                    .fill(presentation.isLast ? Color.clear : bottomConnectorColor)
                    .frame(
                        width: 2,
                        height: max(
                            geometry.size.height -
                                StationTimetableStopTimelineLayout.markerCenterY,
                            0
                        )
                    )
                    .offset(
                        x: connectorX,
                        y: StationTimetableStopTimelineLayout.markerCenterY
                    )

                RouteStopMarker(
                    color: markerColor,
                    isEmphasized: presentation.markerIsEmphasized,
                    showsCenter: presentation.showsMarkerCenter
                )
                .position(
                    x: StationTimetableStopTimelineLayout.markerCenterX,
                    y: StationTimetableStopTimelineLayout.markerCenterY
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var connectorX: CGFloat {
        StationTimetableStopTimelineLayout.markerCenterX - 1
    }

    private var neutralRouteColor: Color {
        .secondary.opacity(0.55)
    }

    private var markerColor: Color {
        presentation.markerIsHighlighted ? .accentColor : neutralRouteColor
    }

    private var topConnectorColor: Color {
        presentation.topConnectorIsHighlighted ? .accentColor : neutralRouteColor
    }

    private var bottomConnectorColor: Color {
        presentation.bottomConnectorIsHighlighted ? .accentColor : neutralRouteColor
    }
}

/// Preserves a shared baseline on one line and centers a wrapped route beside its line name.
struct StationTimetableRouteHeading: View {
    let lineTitle: String
    let route: String
    let isLockout: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            heading(alignment: .firstTextBaseline, keepsRouteOnOneLine: true)
            heading(alignment: .center, keepsRouteOnOneLine: false)
        }
    }

    private func heading(
        alignment: VerticalAlignment,
        keepsRouteOnOneLine: Bool
    ) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            Text(lineTitle)
                .font(.title2.bold())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(route)
                .foregroundStyle(.secondary)
                .lineLimit(keepsRouteOnOneLine ? 1 : nil)
                .fixedSize(horizontal: keepsRouteOnOneLine, vertical: true)

            if isLockout {
                Text("Lockout timetable")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.16), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

/// Keeps either keyed explanations or general notes compact and independently expandable.
struct StationTimetableRemarksDisclosure: View {
    let title: LocalizedStringKey
    let systemImage: String
    let values: [String]
    let calendarContext: [String]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ServiceNotesView(notes: values, calendarContext: calendarContext)
                .textSelection(.enabled)
                .padding(.top, 8)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
        }
        .accessibilityLabel(Text(title))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Aligns the station-timetable service date with the shared timetable-first search header.
struct StationTimetableSearchHeader: View {
    @Binding private var timetable: IDOSTimetable
    @Binding private var date: Date
    @Binding private var wholeWeek: Bool

    private let usesCompactLayout: Bool

    init(
        timetable: Binding<IDOSTimetable>,
        date: Binding<Date>,
        wholeWeek: Binding<Bool>,
        usesCompactLayout: Bool
    ) {
        _timetable = timetable
        _date = date
        _wholeWeek = wholeWeek
        self.usesCompactLayout = usesCompactLayout
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            timetablePicker
            Spacer(minLength: usesCompactLayout ? 8 : 12)
            datePicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timetablePicker: some View {
        SearchTimetablePicker(
            timetable: $timetable,
            allowedTimetables: AppTimetableGroup.stationTimetables,
            usesCompactLayout: usesCompactLayout
        )
    }

    private var datePicker: some View {
        StationTimetableDateSearchControl(date: $date, wholeWeek: $wholeWeek)
    }
}

/// Labels the compact station-timetable date button consistently in every search layout.
struct StationTimetableDateSearchControl: View {
    @Binding var date: Date
    @Binding var wholeWeek: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: SearchFieldHeader.contentHeight, alignment: .leading)

            StationTimetableDatePicker(date: $date, wholeWeek: $wholeWeek)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Keeps the ODIS municipality beside the line whose suggestions it scopes.
struct StationTimetableMunicipalityPicker: View {
    @Binding var municipality: IDOSStationTimetableMunicipality?
    let municipalities: [IDOSStationTimetableMunicipality]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Municipality")
                .font(.caption)
                .foregroundStyle(.secondary)

            StationTimetableMunicipalityPopUpButton(
                municipality: $municipality,
                municipalities: municipalities
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Presents the ODIS municipality with the same native width as the timetable popup above it.
struct StationTimetableMunicipalityPopUpButton: NSViewRepresentable {
    @Binding var municipality: IDOSStationTimetableMunicipality?
    let municipalities: [IDOSStationTimetableMunicipality]

    func makeCoordinator() -> Coordinator {
        Coordinator(municipality: $municipality, municipalities: municipalities)
    }

    func makeNSView(context: Context) -> FixedWidthPopUpButton {
        let button = FixedWidthPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectMunicipality(_:))
        button.setAccessibilityLabel(AppLocalization.string("Municipality"))
        return button
    }

    func updateNSView(_ button: FixedWidthPopUpButton, context: Context) {
        context.coordinator.municipality = $municipality
        context.coordinator.municipalities = municipalities

        let representedMunicipalities = button.itemArray.compactMap {
            $0.representedObject as? String
        }
        let timetableNames = municipalities.map(\.timetableName)
        if representedMunicipalities != timetableNames {
            button.removeAllItems()
            for municipality in municipalities {
                button.addItem(withTitle: municipality.name)
                button.lastItem?.representedObject = municipality.timetableName
            }
        }

        if let municipality,
           let index = municipalities.firstIndex(where: {
               $0.timetableName == municipality.timetableName
           })
        {
            button.selectItem(at: index)
            button.setAccessibilityValue(municipality.name)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView button: FixedWidthPopUpButton,
        context: Context
    ) -> CGSize? {
        button.intrinsicContentSize
    }

    /// Passes the selected native menu item back into the station-timetable search model.
    @MainActor
    final class Coordinator: NSObject {
        var municipality: Binding<IDOSStationTimetableMunicipality?>
        var municipalities: [IDOSStationTimetableMunicipality]

        init(
            municipality: Binding<IDOSStationTimetableMunicipality?>,
            municipalities: [IDOSStationTimetableMunicipality]
        ) {
            self.municipality = municipality
            self.municipalities = municipalities
        }

        @objc func selectMunicipality(_ sender: NSPopUpButton) {
            guard let timetableName = sender.selectedItem?.representedObject as? String,
                  let selected = municipalities.first(where: {
                      $0.timetableName == timetableName
                  })
            else { return }

            municipality.wrappedValue = selected
        }
    }

    /// Keeps the rendered AppKit popup at the shared timetable-control width.
    final class FixedWidthPopUpButton: NSPopUpButton {
        override var intrinsicContentSize: NSSize {
            var size = super.intrinsicContentSize
            size.width = SearchTimetablePicker.controlWidth
            return size
        }
    }
}

/// Uses the shared compact date control without exposing a time unsupported by station timetables.
struct StationTimetableDatePicker: View {
    @Binding var date: Date
    @Binding var wholeWeek: Bool

    var body: some View {
        SearchDatePickerButton(
            title: StationTimetableDatePresentation.title(
                date: date,
                wholeWeek: wholeWeek
            ),
            accessibilityLabel: "Date"
        ) {
            StationTimetableDateEditor(
                date: $date,
                wholeWeek: $wholeWeek
            )
        }
    }
}

/// Keeps the selected date and whole-week scope visible after the compact editor closes.
enum StationTimetableDatePresentation {
    static func title(
        date: Date,
        wholeWeek: Bool,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        let dateTitle = formatter.string(from: date)
        guard wholeWeek else { return dateTitle }
        let wholeWeekTitle = AppLocalization.string("Whole week")
        guard let firstCharacter = wholeWeekTitle.first else { return dateTitle }
        let inlineWholeWeekTitle = String(firstCharacter).lowercased(with: locale) +
            String(wholeWeekTitle.dropFirst())
        return "\(dateTitle) \(inlineWholeWeekTitle)"
    }
}

/// Edits the service date used by either a single-day or whole-week station timetable request.
struct StationTimetableDateEditor: View {
    @Binding var date: Date
    @Binding var wholeWeek: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12) {
                GridRow {
                    Text("Date")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Toggle("Whole week", isOn: $wholeWeek)
                .fixedSize()
        }
        .padding(16)
        .fixedSize(horizontal: true, vertical: true)
    }
}
