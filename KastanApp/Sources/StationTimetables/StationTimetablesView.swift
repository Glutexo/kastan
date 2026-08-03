import Foundation
import Kastan
import SwiftUI

/// Searches and presents IDOS station timetables for MHD and integrated transport systems.
struct StationTimetablesView: View {
    @ObservedObject var model: StationTimetablesViewModel
    let client: any IDOSClienting
    @State private var isSearchFormCollapsed = false

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
                resultsPanel
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .animation(.easeInOut(duration: 0.18), value: isSearchFormCollapsed)
        }
        .focusedSceneValue(\.fillCurrentCommandContext, fillCurrentCommandContext)
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

    private func searchPanel(usesCompactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StationTimetableSearchHeader(
                timetable: timetableBinding,
                date: $model.date,
                wholeWeek: $model.wholeWeek,
                usesCompactLayout: usesCompactLayout
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .placeInputCenter, spacing: 12) {
                    lineField
                    fromField
                    swapButton
                    toField
                }
                VStack(alignment: .leading, spacing: 12) {
                    lineField
                    HStack(alignment: .placeInputCenter, spacing: 12) {
                        fromField
                        swapButton
                        toField
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Spacer(minLength: 0)
                searchButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineField: some View {
        PlaceAutocompleteField(
            title: "Line",
            prompt: "Line number or name",
            text: $model.line,
            timetable: model.timetable,
            scope: .stationTimetableLines,
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
            IDOSRequestFormatting.date(from: model.date),
        ]
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

    private var fillCurrentCommandContext: FillCurrentCommandContext {
        FillCurrentCommandContext(
            enabledActions: FillCurrentAction.supportedActions(for: .stationTimetables),
            perform: fillCurrent
        )
    }

    /// Reveals the editable form before applying today's date from the application menu.
    private func fillCurrent(_ action: FillCurrentAction) {
        guard FillCurrentAction.supportedActions(for: .stationTimetables).contains(action) else { return }
        editSearch()

        switch action {
        case .swapPlaces:
            model.swapDirectionStops()
        case .date:
            model.selectCurrentDate()
        case .fromPlace, .toPlace, .dateAndTime, .time:
            break
        }
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
    private var results: some View {
        if model.isSearching, model.result == nil {
            ProgressView("Loading station timetable…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if let result = model.result {
            stationTimetable(result)
        } else if model.errorMessage == nil {
            EmptyStateView(
                title: "No station timetable yet",
                systemImage: "calendar",
                description: "Choose an MHD line and direction, then start a search."
            )
        }
    }

    private func stationTimetable(_ result: IDOSStationTimetable) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            resultHeader(result)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    stops(result)
                        .frame(minWidth: 280, idealWidth: 330, maxWidth: 380)
                    schedules(result)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 18) {
                    stops(result)
                    schedules(result)
                }
            }

            if !result.notes.isEmpty {
                GroupBox("Notes") {
                    ServiceNotesView(notes: result.notes)
                }
            }
        }
    }

    private func resultHeader(_ result: IDOSStationTimetable) -> some View {
        let title: String
        if let transportMode = result.transportMode {
            title = "\(transportMode.emoji) \(result.lineName)"
        } else {
            title = result.lineName
        }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            Text("\(result.fromStop) → \(result.toStop)")
                .foregroundStyle(.secondary)
            if result.isLockout {
                Text("Lockout timetable")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.16), in: Capsule())
            }
            Spacer()
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
    }

    private func stops(_ result: IDOSStationTimetable) -> some View {
        GroupBox("Stops") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(result.stops.enumerated()), id: \.offset) { index, stop in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            Task { await model.selectStop(at: index) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(minuteOffsetText(stop.minuteOffset))
                                    .font(.callout.bold().monospacedDigit())
                                    .foregroundStyle(stop.isSelected ? Color.accentColor : Color.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                Circle()
                                    .fill(stop.isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                        .fontWeight(stop.isSelected ? .semibold : .regular)
                                        .foregroundStyle(.primary)
                                    if let metadata = stopMetadata(stop) {
                                        Text(metadata)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .padding(.bottom, stop.notes.isEmpty ? 6 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(stop.isSelected || model.isSearching)

                        if !stop.notes.isEmpty {
                            NoteText(stop.notes.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 64)
                                .padding(.trailing, 8)
                                .padding(.bottom, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        stop.isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
            }
        }
    }

    private func schedules(_ result: IDOSStationTimetable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedStop = result.selectedStop {
                Label(selectedStop.name, systemImage: "clock")
                    .font(.headline)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(result.schedules.enumerated()), id: \.offset) { _, schedule in
                        scheduleTable(schedule)
                            .frame(width: 260)
                    }
                }
            }
        }
    }

    private func scheduleTable(_ schedule: IDOSStationTimetableSchedule) -> some View {
        GroupBox(schedule.label) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(schedule.hours.enumerated()), id: \.offset) { _, hour in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(hour.hour)
                            .font(.body.bold().monospacedDigit())
                            .frame(width: 28, alignment: .trailing)
                        Text(hour.departures.isEmpty ? "—" : hour.departures.joined(separator: "  "))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(hour.departures.isEmpty ? .tertiary : .primary)
                    }
                    .padding(.vertical, 3)
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
            SearchTimetablePicker(
                timetable: $timetable,
                allowedTimetables: AppTimetableGroup.stationTimetables,
                usesCompactLayout: usesCompactLayout
            )

            Spacer(minLength: usesCompactLayout ? 8 : 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: SearchFieldHeader.contentHeight, alignment: .leading)

                StationTimetableDatePicker(
                    date: $date,
                    wholeWeek: $wholeWeek
                )
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
