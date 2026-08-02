import AppKit
import Kastan
import SwiftUI

/// Decides whether compact search-field shortcuts should accompany their labels.
enum SearchShortcutPresentation {
    static func isVisible(for modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }
}

/// Adds stable connection-specific controls and full-width details to the shared search layout.
struct JourneySearchControlsSupplement {
    let leading: AnyView
    let modeAligned: AnyView
    let details: AnyView

    init<Leading: View, ModeAligned: View, Details: View>(
        leading: Leading,
        modeAligned: ModeAligned,
        details: Details
    ) {
        self.leading = AnyView(leading)
        self.modeAligned = AnyView(modeAligned)
        self.details = AnyView(details)
    }
}

/// Presents the transport catalog before place-specific input so users choose the search context first.
struct SearchTimetablePicker: View {
    static let pickerWidth: CGFloat = 240

    /// Keeps the favorite close in compact forms and visibly separate when the form has more room.
    static func favoriteSpacing(usesCompactLayout: Bool) -> CGFloat {
        usesCompactLayout ? -8 : 2
    }

    @AppStorage(TimetableFavorites.storageKey) private var serializedTimetableFavorites = "[]"
    @Binding private var timetable: IDOSTimetable

    private let allowedTimetables: [IDOSTimetable]
    private let usesCompactLayout: Bool

    init(
        timetable: Binding<IDOSTimetable>,
        allowedTimetables: [IDOSTimetable] = IDOSTimetable.known,
        usesCompactLayout: Bool
    ) {
        _timetable = timetable
        self.allowedTimetables = allowedTimetables
        self.usesCompactLayout = usesCompactLayout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timetable")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Self.favoriteSpacing(usesCompactLayout: usesCompactLayout)) {
                Picker("Timetable", selection: timetableSlug) {
                    AppTimetablePickerOptions(
                        favoriteSlugs: timetableFavorites.slugs,
                        allowedTimetables: allowedTimetables
                    )
                }
                .labelsHidden()
                .frame(width: Self.pickerWidth, alignment: .leading)

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
                if let selected = allowedTimetables.first(where: { $0.slug == slug }) {
                    timetable = selected
                }
            }
        )
    }
}

/// Keeps date, time, mode, and search actions visually identical across app searches.
struct JourneySearchControls: View {
    /// Balances the large native search button's trailing chrome with the visible leading control inset.
    static let wideSearchButtonTrailingPadding: CGFloat = 5

    /// Leaves enough room for the localized time mode to stay on the compact search row.
    static func searchButtonContentWidth(usesStackedLayout: Bool) -> CGFloat {
        usesStackedLayout ? 80 : 140
    }

    @Binding private var date: Date
    @Binding private var time: Date
    @Binding private var isArrival: Bool

    private let modeLabel: LocalizedStringKey
    private let departureLabel: LocalizedStringKey
    private let arrivalLabel: LocalizedStringKey
    private let usesCurrentDateAndTime: Bool
    private let selectCurrentDateAndTime: () -> Void
    private let isSearching: Bool
    private let canSearch: Bool
    private let usesStackedLayout: Bool
    private let supplement: JourneySearchControlsSupplement?
    private let search: () -> Void

    init(
        date: Binding<Date>,
        time: Binding<Date>,
        isArrival: Binding<Bool>,
        modeLabel: LocalizedStringKey,
        departureLabel: LocalizedStringKey,
        arrivalLabel: LocalizedStringKey,
        usesCurrentDateAndTime: Bool = true,
        selectCurrentDateAndTime: (() -> Void)? = nil,
        isSearching: Bool,
        canSearch: Bool,
        usesStackedLayout: Bool,
        supplement: JourneySearchControlsSupplement? = nil,
        search: @escaping () -> Void
    ) {
        _date = date
        _time = time
        _isArrival = isArrival
        self.modeLabel = modeLabel
        self.departureLabel = departureLabel
        self.arrivalLabel = arrivalLabel
        self.usesCurrentDateAndTime = usesCurrentDateAndTime
        self.selectCurrentDateAndTime = selectCurrentDateAndTime ?? {
            let now = Date.now
            date.wrappedValue = now
            time.wrappedValue = now
        }
        self.isSearching = isSearching
        self.canSearch = canSearch
        self.usesStackedLayout = usesStackedLayout
        self.supplement = supplement
        self.search = search
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if usesStackedLayout {
                    ViewThatFits(in: .horizontal) {
                        stackedHorizontalControls
                            .fixedSize(horizontal: true, vertical: false)

                        compactStackedControls
                    }
                } else if let supplement {
                    horizontalControls(supplement: supplement)
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        dateTimePicker
                        modePicker
                            .frame(width: 175, alignment: .leading)
                        Spacer(minLength: 0)
                        searchButton
                            .padding(.trailing, Self.wideSearchButtonTrailingPadding)
                    }
                }
            }

            if let supplement {
                supplement.details
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Keeps the direct-only shortcut in the same column as the time mode at every wide width.
    private func horizontalControls(supplement: JourneySearchControlsSupplement) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow(alignment: .bottom) {
                dateTimePicker
                modePicker
                    .frame(width: 175, alignment: .leading)
                Spacer(minLength: 0)
                searchButton
                    .padding(.trailing, Self.wideSearchButtonTrailingPadding)
            }

            alignedSupplementalRow(supplement: supplement, modeWidth: 175)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Preserves the column alignment while all primary controls still fit on one compact row.
    @ViewBuilder
    private var stackedHorizontalControls: some View {
        if let supplement {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow(alignment: .bottom) {
                    dateTimePicker
                    modePicker
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    searchButton
                }

                alignedSupplementalRow(supplement: supplement, modeWidth: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                dateTimePicker
                modePicker
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                searchButton
            }
        }
    }

    /// Preserves a readable side-by-side options row when the mode itself moves to a compact row.
    private var compactStackedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                dateTimePicker
                Spacer(minLength: 0)
            }

            if let supplement {
                compactAlignedControls(supplement: supplement)
            } else {
                HStack(spacing: 12) {
                    modePicker
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    searchButton
                }
            }
        }
    }

    /// Reserves the journey-options column when primary controls need separate compact rows.
    private func compactAlignedControls(supplement: JourneySearchControlsSupplement) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Color.clear
                    .frame(height: 0)
                modePicker
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                searchButton
            }

            alignedSupplementalRow(supplement: supplement, modeWidth: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Aligns supplemental controls beneath the journey-instant and time-mode columns.
    private func alignedSupplementalRow(
        supplement: JourneySearchControlsSupplement,
        modeWidth: CGFloat?
    ) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            supplement.leading
                .fixedSize(horizontal: true, vertical: false)
            supplement.modeAligned
                .frame(width: modeWidth, alignment: .leading)
            Color.clear
                .frame(width: 0, height: 0)
            Color.clear
                .frame(width: 0, height: 0)
        }
    }

    /// Keeps the compact instant from gaining width and pushing the adjacent time mode away.
    private var dateTimePicker: some View {
        JourneyDateTimePicker(
            date: $date,
            time: $time,
            usesCurrentDateAndTime: usesCurrentDateAndTime,
            selectCurrentDateAndTime: selectCurrentDateAndTime
        )
        .fixedSize(horizontal: true, vertical: false)
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

/// Combines the independently stored IDOS date and time components for one compact, localized label.
enum JourneyDateTimePresentation {
    static func combinedValue(
        date: Date,
        time: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    static func title(
        date: Date,
        time: Date,
        usesCurrentDateAndTime: Bool,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard !usesCurrentDateAndTime else {
            return AppLocalization.string("Now")
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: combinedValue(date: date, time: time, calendar: calendar))
    }
}

/// Keeps the common journey instant compact until the user opens its date-and-time editor.
struct JourneyDateTimePicker: View {
    static let buttonContentWidth: CGFloat = 150
    static let editorFieldWidth: CGFloat = 180

    @Binding private var date: Date
    @Binding private var time: Date
    @State private var isEditorPresented = false

    private let usesCurrentDateAndTime: Bool
    private let selectCurrentDateAndTime: () -> Void

    init(
        date: Binding<Date>,
        time: Binding<Date>,
        usesCurrentDateAndTime: Bool,
        selectCurrentDateAndTime: @escaping () -> Void
    ) {
        _date = date
        _time = time
        self.usesCurrentDateAndTime = usesCurrentDateAndTime
        self.selectCurrentDateAndTime = selectCurrentDateAndTime
    }

    var body: some View {
        Button {
            if usesCurrentDateAndTime {
                selectCurrentDateAndTime()
            }
            isEditorPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(buttonTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: Self.buttonContentWidth, alignment: .leading)
        }
        .accessibilityLabel(Text("Date and time"))
        .accessibilityValue(Text(buttonTitle))
        .popover(isPresented: $isEditorPresented, arrowEdge: .bottom) {
            editor
        }
    }

    private var buttonTitle: String {
        JourneyDateTimePresentation.title(
            date: date,
            time: time,
            usesCurrentDateAndTime: usesCurrentDateAndTime
        )
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date and time")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Date")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .frame(width: Self.editorFieldWidth, alignment: .leading)
                }

                GridRow {
                    Text("Time")
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .frame(width: Self.editorFieldWidth, alignment: .leading)
                }
            }

            Divider()

            HStack {
                Button("Now") {
                    selectCurrentDateAndTime()
                    isEditorPresented = false
                }
                Spacer()
                Button("Done") {
                    isEditorPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

/// Reveals a compact field shortcut without changing the search row's measured layout.
struct SearchFieldHeader: View {
    let title: LocalizedStringKey
    let shortcutTitle: LocalizedStringKey
    let showsShortcut: Bool
    let isPerformingShortcut: Bool
    let isShortcutDisabled: Bool
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        shortcutTitle: LocalizedStringKey,
        showsShortcut: Bool,
        isPerformingShortcut: Bool = false,
        isShortcutDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.shortcutTitle = shortcutTitle
        self.showsShortcut = showsShortcut
        self.isPerformingShortcut = isPerformingShortcut
        self.isShortcutDisabled = isShortcutDisabled
        self.action = action
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 16, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .font(.caption)
                        .fixedSize(horizontal: true, vertical: false)
                        .hidden()

                    if showsShortcut {
                        Button(action: action) {
                            Text(shortcutTitle)
                                .opacity(isPerformingShortcut ? 0 : 1)
                                .overlay {
                                    if isPerformingShortcut {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .fixedSize()
                            .disabled(isShortcutDisabled)
                            .transition(.opacity)
                    }
                }
                .frame(height: 16, alignment: .leading)
                .animation(.easeInOut(duration: 0.1), value: showsShortcut)
            }
    }
}

/// Mirrors the live Option state into SwiftUI for controls with modifier-dependent alternate actions.
struct OptionModifierMonitor: NSViewRepresentable {
    @Binding var isPressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPressed: $isPressed)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.startMonitoring()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPressed = $isPressed
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator: NSObject {
        var isPressed: Binding<Bool>
        private var eventMonitor: Any?

        init(isPressed: Binding<Bool>) {
            self.isPressed = isPressed
        }

        func startMonitoring() {
            guard eventMonitor == nil else { return }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
                [weak self] event in
                self?.update(
                    SearchShortcutPresentation.isVisible(for: event.modifierFlags)
                )
                return event
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidResignActive),
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func applicationDidBecomeActive() {
            update(SearchShortcutPresentation.isVisible(for: NSEvent.modifierFlags))
        }

        @objc private func applicationDidResignActive() {
            update(false)
        }

        private func update(_ newValue: Bool) {
            guard isPressed.wrappedValue != newValue else { return }
            isPressed.wrappedValue = newValue
        }
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
