import AppKit
import Kastan
import SwiftUI

/// Decides whether compact search-field shortcuts should accompany their labels.
enum SearchShortcutPresentation {
    static func isVisible(for modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.option)
    }
}

/// Adds connection-specific controls to the shared search layout without losing its column alignment.
struct JourneySearchControlsSupplement {
    let leading: AnyView
    let modeAligned: AnyView

    init<Leading: View, ModeAligned: View>(leading: Leading, modeAligned: ModeAligned) {
        self.leading = AnyView(leading)
        self.modeAligned = AnyView(modeAligned)
    }
}

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
    @State private var showsDateTimeShortcuts = SearchShortcutPresentation.isVisible(
        for: NSEvent.modifierFlags
    )

    private let modeLabel: LocalizedStringKey
    private let departureLabel: LocalizedStringKey
    private let arrivalLabel: LocalizedStringKey
    private let isSearching: Bool
    private let canSearch: Bool
    private let usesStackedLayout: Bool
    private let supplement: JourneySearchControlsSupplement?
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
        supplement: JourneySearchControlsSupplement? = nil,
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
        self.supplement = supplement
        self.search = search
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 12) {
                    timetablePicker
                        .frame(maxWidth: 360, alignment: .leading)

                    ViewThatFits(in: .horizontal) {
                        stackedHorizontalControls

                        compactStackedControls
                    }
                }
            } else if let supplement {
                horizontalControls(supplement: supplement)
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
        .background {
            OptionModifierMonitor(isPressed: $showsDateTimeShortcuts)
                .frame(width: 0, height: 0)
        }
    }

    /// Uses the same grid column for the time mode and its supplemental shortcut.
    private func horizontalControls(supplement: JourneySearchControlsSupplement) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow(alignment: .bottom) {
                timetablePicker
                    .frame(width: 240)
                datePicker
                timePicker
                modePicker
                    .frame(width: 175)
                Spacer(minLength: 0)
                searchButton
            }

            supplementalRow(supplement: supplement, leadingColumnCount: 3, modeWidth: 175)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Keeps the supplemental shortcut below the mode picker while all controls still fit on one row.
    @ViewBuilder
    private var stackedHorizontalControls: some View {
        if let supplement {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow(alignment: .bottom) {
                    datePicker
                    timePicker
                    modePicker
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    searchButton
                }

                supplementalRow(supplement: supplement, leadingColumnCount: 2, modeWidth: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                datePicker
                timePicker
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
                datePicker
                timePicker
                Spacer(minLength: 0)
            }

            if let supplement {
                ViewThatFits(in: .horizontal) {
                    compactAlignedControls(supplement: supplement)
                    compactNaturalControls(supplement: supplement)
                }
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

    /// Reserves the collapsed journey-options width so the checkbox remains directly below the time mode.
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

            GridRow(alignment: .top) {
                supplement.leading
                supplement.modeAligned
                Color.clear
                    .frame(height: 0)
                Color.clear
                    .frame(height: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Lets an expanded journey editor use the compact width even when its fields outgrow the aligned columns.
    private func compactNaturalControls(supplement: JourneySearchControlsSupplement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                modePicker
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                searchButton
            }

            HStack(alignment: .top, spacing: 12) {
                supplement.leading
                Spacer(minLength: 0)
                supplement.modeAligned
            }
        }
    }

    /// Spans the controls before the mode column and retains the trailing flexible and search columns.
    private func supplementalRow(
        supplement: JourneySearchControlsSupplement,
        leadingColumnCount: Int,
        modeWidth: CGFloat?
    ) -> some View {
        GridRow(alignment: .top) {
            supplement.leading
                .gridCellColumns(leadingColumnCount)
            supplement.modeAligned
                .frame(width: modeWidth, alignment: .leading)
            Color.clear
                .frame(height: 0)
            Color.clear
                .frame(height: 0)
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
            SearchFieldHeader(
                title: "Date",
                shortcutTitle: "Today",
                showsShortcut: showsDateTimeShortcuts
            ) {
                date = .now
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
        }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            SearchFieldHeader(
                title: "Time",
                shortcutTitle: "Now",
                showsShortcut: showsDateTimeShortcuts
            ) {
                time = .now
            }
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

/// Mirrors the live Option state into SwiftUI while the editable search form is visible.
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
