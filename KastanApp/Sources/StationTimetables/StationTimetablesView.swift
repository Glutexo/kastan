import Kastan
import SwiftUI

/// Searches and presents IDOS station timetables for MHD and integrated transport systems.
struct StationTimetablesView: View {
    @AppStorage(TimetableFavorites.storageKey) private var serializedTimetableFavorites = "[]"
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
                    searchPanel
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
        .navigationTitle("Station timetables")
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

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 12) {
                    timetablePicker
                    datePicker
                    wholeWeekToggle
                    Spacer(minLength: 8)
                    searchButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    timetablePicker
                    HStack(alignment: .bottom, spacing: 12) {
                        datePicker
                        wholeWeekToggle
                        Spacer(minLength: 8)
                        searchButton
                    }
                }
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
        Button {
            let previousFrom = model.from
            model.from = model.to
            model.to = previousFrom
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .alignmentGuide(.placeInputCenter) { dimensions in
            dimensions[VerticalAlignment.center]
        }
        .accessibilityLabel("Swap direction stops")
        .help("Swap direction stops")
    }

    private var timetablePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timetable")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Picker("Timetable", selection: timetableSlug) {
                    AppTimetablePickerOptions(
                        favoriteSlugs: favorites.slugs,
                        allowedTimetables: AppTimetableGroup.stationTimetables
                    )
                }
                .labelsHidden()
                .frame(width: 240)

                Button {
                    var updated = favorites
                    updated.toggle(model.timetable)
                    serializedTimetableFavorites = updated.serialized
                } label: {
                    Image(systemName: favorites.contains(model.timetable) ? "star.fill" : "star")
                        .foregroundStyle(favorites.contains(model.timetable) ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(favoriteButtonLabel)
                .help(favoriteButtonLabel)
            }
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Date", selection: $model.date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
        }
    }

    private var wholeWeekToggle: some View {
        Toggle("Whole week", isOn: $model.wholeWeek)
            .fixedSize()
            .padding(.bottom, 5)
    }

    private var searchButton: some View {
        Button(action: performSearch) {
            Group {
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            .frame(width: 140)
            .frame(minHeight: 26)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canSearch)
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

    private var favorites: TimetableFavorites {
        TimetableFavorites(serialized: serializedTimetableFavorites)
    }

    private var favoriteButtonLabel: LocalizedStringKey {
        favorites.contains(model.timetable)
            ? "Remove timetable from favorites"
            : "Add timetable to favorites"
    }

    private var timetableSlug: Binding<String> {
        Binding(
            get: { model.timetable.slug },
            set: { slug in model.selectTimetable(slug: slug) }
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
                    BulletedTextList(items: result.notes)
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
                Menu {
                    ShareLink(item: url) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: url) {
                        Label("Open in IDOS", systemImage: "arrow.up.right.square")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private func stops(_ result: IDOSStationTimetable) -> some View {
        GroupBox("Stops") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(result.stops.enumerated()), id: \.offset) { index, stop in
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
                                if !stop.notes.isEmpty {
                                    Text(stop.notes.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            stop.isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(stop.isSelected || model.isSearching)
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
