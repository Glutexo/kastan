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
    let adjacent: AnyView
    let details: AnyView

    init<Leading: View, Adjacent: View, Details: View>(
        leading: Leading,
        adjacent: Adjacent,
        details: Details
    ) {
        self.leading = AnyView(leading)
        self.adjacent = AnyView(adjacent)
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

/// Keeps the timetable context and journey instant on one stable row across journey searches.
struct JourneySearchHeader: View {
    @Binding private var timetable: IDOSTimetable
    @Binding private var date: Date
    @Binding private var time: Date
    @Binding private var isArrival: Bool

    private let modeLabel: String
    private let departureLabel: String
    private let arrivalLabel: String
    private let usesCurrentDateAndTime: Bool
    private let selectCurrentDateAndTime: () -> Void
    private let usesCompactLayout: Bool

    init(
        timetable: Binding<IDOSTimetable>,
        date: Binding<Date>,
        time: Binding<Date>,
        isArrival: Binding<Bool>,
        modeLabel: String,
        departureLabel: String,
        arrivalLabel: String,
        usesCurrentDateAndTime: Bool,
        selectCurrentDateAndTime: @escaping () -> Void,
        usesCompactLayout: Bool
    ) {
        _timetable = timetable
        _date = date
        _time = time
        _isArrival = isArrival
        self.modeLabel = modeLabel
        self.departureLabel = departureLabel
        self.arrivalLabel = arrivalLabel
        self.usesCurrentDateAndTime = usesCurrentDateAndTime
        self.selectCurrentDateAndTime = selectCurrentDateAndTime
        self.usesCompactLayout = usesCompactLayout
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            SearchTimetablePicker(
                timetable: $timetable,
                usesCompactLayout: usesCompactLayout
            )

            Spacer(minLength: usesCompactLayout ? 8 : 12)

            JourneyDateTimePicker(
                date: $date,
                time: $time,
                isArrival: $isArrival,
                modeLabel: modeLabel,
                departureLabel: departureLabel,
                arrivalLabel: arrivalLabel,
                usesCurrentDateAndTime: usesCurrentDateAndTime,
                selectCurrentDateAndTime: selectCurrentDateAndTime
            )
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: -JourneySearchControls.trailingControlInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keeps search actions and connection-specific options visually identical across journey searches.
struct JourneySearchControls: View {
    /// Pulls native button chrome back to the same visible trailing edge as the text fields.
    static let trailingControlInset: CGFloat = 10

    /// Keeps the search action compact in narrow forms and comfortably wide otherwise.
    static func searchButtonContentWidth(usesStackedLayout: Bool) -> CGFloat {
        usesStackedLayout ? 80 : 140
    }

    private let isSearching: Bool
    private let canSearch: Bool
    private let usesStackedLayout: Bool
    private let supplement: JourneySearchControlsSupplement?
    private let search: () -> Void

    init(
        isSearching: Bool,
        canSearch: Bool,
        usesStackedLayout: Bool,
        supplement: JourneySearchControlsSupplement? = nil,
        search: @escaping () -> Void
    ) {
        self.isSearching = isSearching
        self.canSearch = canSearch
        self.usesStackedLayout = usesStackedLayout
        self.supplement = supplement
        self.search = search
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let supplement {
                controlsRow(supplement: supplement)
                supplement.details
            } else {
                searchRow
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Keeps the primary action at the trailing edge after the journey editor moves into the header.
    private var searchRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Spacer(minLength: 0)
            searchButton
                .offset(x: -Self.trailingControlInset)
        }
    }

    /// Shares one visual level between journey options, their shortcut, and the primary action.
    private func controlsRow(supplement: JourneySearchControlsSupplement) -> some View {
        HStack(alignment: .center, spacing: 12) {
            supplement.leading
                .fixedSize(horizontal: true, vertical: false)
            supplement.adjacent
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            searchButton
                .offset(x: -Self.trailingControlInset)
        }
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

    /// Keeps the selected journey mode visible beside either Now or the chosen localized instant.
    static func closedTitle(
        date: Date,
        time: Date,
        isArrival: Bool,
        departureLabel: String,
        arrivalLabel: String,
        usesCurrentDateAndTime: Bool,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let mode = AppLocalization.string(isArrival ? arrivalLabel : departureLabel)
        let instant = title(
            date: date,
            time: time,
            usesCurrentDateAndTime: usesCurrentDateAndTime,
            locale: locale,
            calendar: calendar
        )
        let displayedInstant: String
        if usesCurrentDateAndTime, let firstCharacter = instant.first {
            displayedInstant = String(firstCharacter).lowercased(with: locale) +
                String(instant.dropFirst())
        } else {
            displayedInstant = instant
        }
        return "\(mode) \(displayedInstant)"
    }
}

/// Keeps the common journey instant compact until the user opens its date-and-time editor.
struct JourneyDateTimePicker: View {
    static let buttonContentWidth: CGFloat = 190

    @Binding private var date: Date
    @Binding private var time: Date
    @Binding private var isArrival: Bool
    @State private var isEditorPresented = false

    private let modeLabel: String
    private let departureLabel: String
    private let arrivalLabel: String
    private let usesCurrentDateAndTime: Bool
    private let selectCurrentDateAndTime: () -> Void

    init(
        date: Binding<Date>,
        time: Binding<Date>,
        isArrival: Binding<Bool>,
        modeLabel: String,
        departureLabel: String,
        arrivalLabel: String,
        usesCurrentDateAndTime: Bool,
        selectCurrentDateAndTime: @escaping () -> Void
    ) {
        _date = date
        _time = time
        _isArrival = isArrival
        self.modeLabel = modeLabel
        self.departureLabel = departureLabel
        self.arrivalLabel = arrivalLabel
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
                    .truncationMode(.middle)
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
        JourneyDateTimePresentation.closedTitle(
            date: date,
            time: time,
            isArrival: isArrival,
            departureLabel: departureLabel,
            arrivalLabel: arrivalLabel,
            usesCurrentDateAndTime: usesCurrentDateAndTime
        )
    }

    private var editor: some View {
        JourneyDateTimeEditor(
            date: $date,
            time: $time,
            isArrival: $isArrival,
            modeLabel: modeLabel,
            departureLabel: departureLabel,
            arrivalLabel: arrivalLabel,
            selectCurrentDateAndTime: selectCurrentDateAndTime,
            done: { isEditorPresented = false }
        )
    }
}

/// Edits the complete journey instant and whether that instant means departure or arrival.
struct JourneyDateTimeEditor: View {
    @Binding var date: Date
    @Binding var time: Date
    @Binding var isArrival: Bool

    let modeLabel: String
    let departureLabel: String
    let arrivalLabel: String
    let selectCurrentDateAndTime: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(AppLocalization.string(modeLabel), selection: $isArrival) {
                Text(AppLocalization.string(departureLabel)).tag(false)
                Text(AppLocalization.string(arrivalLabel)).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Date")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .fixedSize(horizontal: true, vertical: false)
                }

                GridRow {
                    Text("Time")
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Divider()

            HStack {
                Button("Now") {
                    selectCurrentDateAndTime()
                    done()
                }
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .fixedSize(horizontal: true, vertical: true)
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
