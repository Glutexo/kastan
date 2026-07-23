import Kastan
import SwiftUI

/// Keeps timetable, date, time, mode, and search actions visually identical across app searches.
struct JourneySearchControls: View {
    /// Overlaps the controls' empty edge insets so the favorite sits beside the visible picker.
    static func timetableFavoriteSpacing(usesStackedLayout _: Bool) -> CGFloat {
        -8
    }

    /// Leaves enough room for the localized time mode to stay on the compact search row.
    static func searchButtonContentWidth(usesStackedLayout: Bool) -> CGFloat {
        usesStackedLayout ? 120 : 140
    }

    @AppStorage(TimetableFavorites.storageKey) private var serializedTimetableFavorites = "[]"
    @Binding private var timetable: IDOSTimetable
    @Binding private var date: Date
    @Binding private var time: Date
    @Binding private var isArrival: Bool

    private let modeLabel: LocalizedStringKey
    private let departureLabel: LocalizedStringKey
    private let arrivalLabel: LocalizedStringKey
    private let isSearching: Bool
    private let canSearch: Bool
    private let usesStackedLayout: Bool
    private let search: () -> Void

    init(
        timetable: Binding<IDOSTimetable>,
        date: Binding<Date>,
        time: Binding<Date>,
        isArrival: Binding<Bool>,
        modeLabel: LocalizedStringKey,
        departureLabel: LocalizedStringKey,
        arrivalLabel: LocalizedStringKey,
        isSearching: Bool,
        canSearch: Bool,
        usesStackedLayout: Bool,
        search: @escaping () -> Void
    ) {
        _timetable = timetable
        _date = date
        _time = time
        _isArrival = isArrival
        self.modeLabel = modeLabel
        self.departureLabel = departureLabel
        self.arrivalLabel = arrivalLabel
        self.isSearching = isSearching
        self.canSearch = canSearch
        self.usesStackedLayout = usesStackedLayout
        self.search = search
    }

    var body: some View {
        if usesStackedLayout {
            VStack(alignment: .leading, spacing: 12) {
                timetablePicker
                    .frame(maxWidth: 360, alignment: .leading)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        datePicker
                        timePicker
                        modePicker
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        searchButton
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            datePicker
                            timePicker
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 12) {
                            modePicker
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            searchButton
                        }
                    }
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                timetablePicker
                    .frame(width: 240)
                datePicker
                timePicker
                modePicker
                    .frame(width: 175)
                Spacer(minLength: 0)
                searchButton
            }
        }
    }

    private var timetablePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timetable")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Self.timetableFavoriteSpacing(usesStackedLayout: usesStackedLayout)) {
                Picker("Timetable", selection: timetableSlug) {
                    AppTimetablePickerOptions(favoriteSlugs: timetableFavorites.slugs)
                }
                .labelsHidden()
                .frame(width: usesStackedLayout ? 240 : 204, alignment: .leading)

                Button {
                    toggleTimetableFavorite()
                } label: {
                    Image(systemName: isTimetableFavorite ? "star.fill" : "star")
                        .foregroundStyle(isTimetableFavorite ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(favoriteButtonLabel))
                .help(Text(favoriteButtonLabel))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var timetableFavorites: TimetableFavorites {
        TimetableFavorites(serialized: serializedTimetableFavorites)
    }

    private var isTimetableFavorite: Bool {
        timetableFavorites.contains(timetable)
    }

    private var favoriteButtonLabel: LocalizedStringKey {
        isTimetableFavorite ? "Remove timetable from favorites" : "Add timetable to favorites"
    }

    private func toggleTimetableFavorite() {
        var favorites = timetableFavorites
        favorites.toggle(timetable)
        serializedTimetableFavorites = favorites.serialized
    }

    private var timetableSlug: Binding<String> {
        Binding(
            get: { timetable.slug },
            set: { slug in
                if let selected = IDOSTimetable.known.first(where: { $0.slug == slug }) {
                    timetable = selected
                }
            }
        )
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
        }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private var modePicker: some View {
        Picker(modeLabel, selection: $isArrival) {
            Text(departureLabel).tag(false)
            Text(arrivalLabel).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var searchButton: some View {
        Button(action: search) {
            Group {
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            .frame(width: Self.searchButtonContentWidth(usesStackedLayout: usesStackedLayout))
            .frame(minHeight: 26)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!canSearch)
    }
}

/// Replaces an executed search form with one low native row until the user chooses to edit it.
struct SearchSummaryBar: View {
    let summary: SearchSummaryPresentation
    let systemImage: String
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button(action: edit) {
                Label("Edit search", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .help("Edit search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}
