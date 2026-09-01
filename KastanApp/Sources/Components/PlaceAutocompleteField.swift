import Kastan
import SwiftUI

private struct PlaceInputCenterAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

extension VerticalAlignment {
    /// Aligns adjacent actions with the input control rather than its caption or suggestions.
    static let placeInputCenter = VerticalAlignment(PlaceInputCenterAlignment.self)
}

/// Gives every pair of place inputs the same borderless direction-swap affordance.
struct PlaceInputSwapButton: View {
    static let iconSize: CGFloat = 24

    private let accessibilityLabel: LocalizedStringKey
    private let action: () -> Void

    init(
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left.arrow.right")
                .frame(width: Self.iconSize, height: Self.iconSize)
        }
        .buttonStyle(.borderless)
        .alignmentGuide(.placeInputCenter) { dimensions in
            dimensions[VerticalAlignment.center]
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .help(Text(accessibilityLabel))
    }
}

/// Routes each autocomplete field to the active data-source operation matching its product input.
enum PlaceSuggestionScope {
    case places
    case stations
    case stationTimetableLines
    case stationTimetableStops

    var requiredCapability: TransitDataSourceCapability {
        switch self {
        case .places:
            .placeSuggestions
        case .stations:
            .stationSearch
        case .stationTimetableLines, .stationTimetableStops:
            .stationTimetables
        }
    }
}

/// Debounces provider suggestions so typing does not issue a request for every keystroke.
@MainActor
final class PlaceSuggestionsModel: ObservableObject {
    private static let visibleSuggestionLimit = 6
    private static let placeSuggestionRequestLimit = 30

    @Published private(set) var suggestions: [TransitSuggestion] = []
    @Published private(set) var isLoading = false

    private let client: any TransitDataSource
    private let scope: PlaceSuggestionScope
    private var task: Task<Void, Never>?
    private var latestQuery = ""
    private var fetchedSuggestions: [TransitSuggestion] = []
    private var visibility = PlaceSuggestionVisibility.defaultValue

    init(client: any TransitDataSource, scope: PlaceSuggestionScope) {
        self.client = client
        self.scope = scope
    }

    deinit {
        task?.cancel()
    }

    func update(
        query: String,
        timetable: TransitTimetable,
        line: String? = nil,
        municipality: TransitStationTimetableMunicipality? = nil,
        visibility: PlaceSuggestionVisibility = .defaultValue
    ) {
        task?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        latestQuery = query
        self.visibility = visibility

        guard client.descriptor.supports(scope.requiredCapability) else {
            fetchedSuggestions = []
            suggestions = []
            isLoading = false
            return
        }

        let minimumLength = scope == .stationTimetableLines ? 1 : 2
        guard query.count >= minimumLength else {
            fetchedSuggestions = []
            suggestions = []
            isLoading = false
            return
        }

        isLoading = true
        task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else {
                    return
                }
                let suggestions: [TransitSuggestion] = switch self.scope {
                case .places:
                    try await self.client.suggest(
                        prefix: query,
                        limit: Self.placeSuggestionRequestLimit,
                        timetable: timetable
                    )
                case .stations:
                    try await self.client.searchStations(
                        prefix: query,
                        limit: Self.visibleSuggestionLimit,
                        timetable: timetable
                    )
                case .stationTimetableLines:
                    try await self.client.searchStationTimetableLines(
                        prefix: query,
                        limit: Self.visibleSuggestionLimit,
                        timetable: timetable,
                        municipality: municipality
                    )
                case .stationTimetableStops:
                    if let line, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try await self.client.searchStationTimetableStops(
                            prefix: query,
                            line: line,
                            limit: Self.visibleSuggestionLimit,
                            timetable: timetable,
                            municipality: municipality
                        )
                    } else {
                        [TransitSuggestion]()
                    }
                }
                guard !Task.isCancelled, self.latestQuery == query else {
                    return
                }
                self.fetchedSuggestions = suggestions
                self.publishVisibleSuggestions()
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.latestQuery == query else {
                    return
                }
                self.fetchedSuggestions = []
                self.suggestions = []
                self.isLoading = false
            }
        }
    }

    /// Refilters the last response immediately when its application-wide menu choice changes.
    func updateVisibility(_ visibility: PlaceSuggestionVisibility) {
        self.visibility = visibility
        publishVisibleSuggestions()
    }

    func selectedSuggestion() {
        task?.cancel()
        fetchedSuggestions = []
        suggestions = []
        isLoading = false
    }

    private func publishVisibleSuggestions() {
        let visible = scope == .places
            ? fetchedSuggestions.filter(visibility.includes)
            : fetchedSuggestions
        suggestions = Array(visible.prefix(Self.visibleSuggestionLimit))
    }
}

/// Defines the persisted choices that can hide non-station place types from connection suggestions.
enum PlaceSuggestionVisibilityPreference {
    static let addressesStorageKey = "showsAddressSuggestions"
    static let boroughsStorageKey = "showsBoroughSuggestions"
    static let municipalitiesStorageKey = "showsMunicipalitySuggestions"
    static let defaultValue = true
}

/// Filters only the explicitly configurable IDOS place types while retaining every station and stop.
struct PlaceSuggestionVisibility: Equatable {
    var showsAddresses: Bool
    var showsBoroughs: Bool
    var showsMunicipalities: Bool

    static let defaultValue = Self(
        showsAddresses: PlaceSuggestionVisibilityPreference.defaultValue,
        showsBoroughs: PlaceSuggestionVisibilityPreference.defaultValue,
        showsMunicipalities: PlaceSuggestionVisibilityPreference.defaultValue
    )

    func includes(_ suggestion: TransitSuggestion) -> Bool {
        switch PlaceSuggestionKind(description: suggestion.description) {
        case .address:
            showsAddresses
        case .borough:
            showsBoroughs
        case .municipality:
            showsMunicipalities
        case .train, .bus, .publicTransport, .stop, .station, .place:
            true
        }
    }
}

private struct PlaceSuggestionVisibilityEnvironmentKey: EnvironmentKey {
    static let defaultValue = PlaceSuggestionVisibility.defaultValue
}

extension EnvironmentValues {
    /// Propagates the application-wide place-suggestion menu choices to connection inputs.
    var placeSuggestionVisibility: PlaceSuggestionVisibility {
        get { self[PlaceSuggestionVisibilityEnvironmentKey.self] }
        set { self[PlaceSuggestionVisibilityEnvironmentKey.self] = newValue }
    }
}

/// Classifies an exact autocomplete choice for a concise visible identity marker.
enum PlaceSuggestionKind: Equatable {
    case municipality
    case borough
    case train
    case bus
    case publicTransport
    case stop
    case address
    case station
    case place

    init(description: String?) {
        let description = description ?? ""
        let metadata = description
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if metadata.contains("municipality") || metadata.contains("city") {
            self = .municipality
        } else if metadata.contains("borough") {
            self = .borough
        } else if metadata.contains("address") {
            self = .address
        } else if metadata.contains("trains") || description.localizedCaseInsensitiveContains("railway") {
            self = .train
        } else if metadata.contains("buses") || metadata.contains("bus") {
            self = .bus
        } else if metadata.contains("pt") || metadata.contains("urban public transport") {
            self = .publicTransport
        } else if metadata.contains("stop") || metadata.contains(where: { $0.hasPrefix("stop (") }) {
            self = .stop
        } else if metadata.contains("station") || metadata.contains(where: { $0.hasPrefix("station (") }) {
            self = .station
        } else {
            self = .place
        }
    }

    var localizedName: String {
        AppLocalization.string(localizationKey)
    }

    var localizedSuffix: String {
        "(\(localizedName))"
    }

    var emoji: String {
        switch self {
        case .municipality:
            "🏘️"
        case .borough:
            "🏙️"
        case .train:
            "🚆"
        case .bus:
            "🚌"
        case .publicTransport:
            "🚋"
        case .stop:
            "🚏"
        case .station:
            "🚉"
        case .address, .place:
            "📍"
        }
    }

    private var localizationKey: String {
        switch self {
        case .municipality:
            "municipality"
        case .borough:
            "borough"
        case .train:
            "train"
        case .bus:
            "bus"
        case .publicTransport:
            "public transport"
        case .stop:
            "stop"
        case .address:
            "address"
        case .station:
            "station"
        case .place:
            "place"
        }
    }
}

/// Keeps the exact provider-owned object and any applicable user-facing type while the field remains unchanged.
struct PlaceFieldSelection: Equatable {
    let placeSelection: TransitPlaceSelection
    let kind: PlaceSuggestionKind?

    init(placeSelection: TransitPlaceSelection, kind: PlaceSuggestionKind?) {
        self.placeSelection = placeSelection
        self.kind = kind
    }

    init(idosSelection: TransitPlaceSelection, kind: PlaceSuggestionKind?) {
        self.init(placeSelection: idosSelection, kind: kind)
    }

    init?(suggestion: TransitSuggestion) {
        guard let placeSelection = TransitPlaceSelection(suggestion: suggestion) else {
            return nil
        }
        self.init(
            placeSelection: placeSelection,
            kind: PlaceSuggestionKind(description: suggestion.description)
        )
    }

    var text: String {
        placeSelection.text
    }

    var isCurrentLocation: Bool {
        placeSelection.isCurrentLocation
    }

    /// Historical spelling retained while persisted app state migrates to provider-neutral terminology.
    var idosSelection: TransitPlaceSelection {
        placeSelection
    }
}

/// Converts raw IDOS suggestion metadata into a localized, deduplicated app row.
struct PlaceSuggestionPresentation: Equatable {
    let kind: PlaceSuggestionKind
    let emoji: String
    let detail: String?

    init(
        suggestion: TransitSuggestion,
        scope: PlaceSuggestionScope = .places,
        countryLanguage: TransitLanguage = AppLanguagePreference.transitLanguage
    ) {
        let rawDescription = suggestion.description ?? ""
        if case .stationTimetableLines = scope {
            (kind, emoji) = Self.stationTimetableLineIdentity(for: suggestion)
        } else {
            kind = PlaceSuggestionKind(description: rawDescription)
            emoji = kind.emoji
        }

        var components = rawDescription
            .split(separator: ",")
            .map { Self.localizedComponent(String($0), countryLanguage: countryLanguage) }
            .filter { !$0.isEmpty }

        if let region = suggestion.region?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
            components.append(Self.localizedComponent(region, countryLanguage: countryLanguage))
        }

        var uniqueComponents: [String] = []
        for component in components where !uniqueComponents.contains(where: {
            $0.compare(component, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            uniqueComponents.append(component)
        }

        detail = uniqueComponents.isEmpty ? nil : uniqueComponents.joined(separator: " · ")
    }

    /// Uses IDOS's transport metadata for a line instead of presenting its terminal-pair description as a place.
    private static func stationTimetableLineIdentity(
        for suggestion: TransitSuggestion
    ) -> (kind: PlaceSuggestionKind, emoji: String) {
        let lineName = suggestion.text
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        if lineName.contains("trolleybus") || lineName.contains("trolejbus") {
            return (.publicTransport, "🚎")
        }
        if lineName.contains("metro") || lineName.contains("subway") {
            return (.publicTransport, "🚇")
        }
        if lineName.contains("tram") || lineName.contains("streetcar") || lineName.contains("tramvaj") {
            return (.publicTransport, "🚋")
        }
        if lineName.contains("train") || lineName.contains("vlak") {
            return (.train, "🚆")
        }
        if lineName.contains("bus") || lineName.contains("autobus") {
            return (.bus, "🚌")
        }

        switch suggestion.iconId {
        case 4:
            return (.bus, "🚌")
        case 5:
            return (.publicTransport, "🚇")
        case 14:
            return (.train, "🚆")
        case 15:
            return (.publicTransport, "🚋")
        default:
            return (.publicTransport, "🛣️")
        }
    }

    private static func localizedComponent(
        _ component: String,
        countryLanguage: TransitLanguage
    ) -> String {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.lowercased()

        switch value {
        case "station":
            return AppLocalization.string("station")
        case "stop":
            return AppLocalization.string("stop")
        case "trains":
            return AppLocalization.string("trains")
        case "buses":
            return AppLocalization.string("buses")
        case "municipality", "city":
            return AppLocalization.string("municipality")
        case "borough":
            return AppLocalization.string("borough")
        case "address":
            return AppLocalization.string("address")
        case "pt", "urban public transport":
            return AppLocalization.string("public transport")
        default:
            if value.hasPrefix("district ") {
                return AppLocalization.string("district %@", String(trimmed.dropFirst("district ".count)))
            }
            if value.hasPrefix("stop (") {
                return "\(AppLocalization.string("stop"))\(trimmed.dropFirst("stop".count))"
            }
            if value.hasPrefix("station (") {
                return "\(AppLocalization.string("station"))\(trimmed.dropFirst("station".count))"
            }
            if let country = AppLanguagePreference.localizedCountryName(
                fromEnglishName: trimmed,
                language: countryLanguage
            ) {
                return country
            }
            return trimmed
        }
    }
}

/// Makes the complete visual suggestion row select the represented IDOS object.
struct PlaceSuggestionButton: View {
    let suggestion: TransitSuggestion
    let scope: PlaceSuggestionScope
    let action: () -> Void

    init(
        suggestion: TransitSuggestion,
        scope: PlaceSuggestionScope = .places,
        action: @escaping () -> Void
    ) {
        self.suggestion = suggestion
        self.scope = scope
        self.action = action
    }

    var body: some View {
        let presentation = PlaceSuggestionPresentation(suggestion: suggestion, scope: scope)

        Button(action: action) {
            HStack(spacing: 10) {
                Text(presentation.emoji)
                    .font(.title3)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.text)
                        .foregroundStyle(.primary)
                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Presents a native text field with IDOS suggestions directly below the current input.
/// A title can be omitted when the field is embedded in a separately labeled row editor.
struct PlaceAutocompleteField: View {
    @Environment(\.placeSuggestionVisibility) private var placeSuggestionVisibility

    let title: LocalizedStringKey?
    let prompt: LocalizedStringKey
    @Binding var text: String
    let selection: Binding<PlaceFieldSelection?>?
    let timetable: TransitTimetable
    let suggestionScope: PlaceSuggestionScope
    let stationTimetableLine: String?
    let stationTimetableMunicipality: TransitStationTimetableMunicipality?
    let onSelection: ((TransitSuggestion) -> Void)?
    let headerShortcutTitle: LocalizedStringKey?
    let showsHeaderShortcut: Bool
    let isPerformingHeaderShortcut: Bool
    let isHeaderShortcutDisabled: Bool
    let headerShortcutAction: (() -> Void)?

    @StateObject private var model: PlaceSuggestionsModel
    @FocusState private var isFocused: Bool
    @State private var inputWidth: CGFloat = 320

    init(
        title: LocalizedStringKey? = nil,
        prompt: LocalizedStringKey,
        text: Binding<String>,
        selection: Binding<PlaceFieldSelection?>? = nil,
        timetable: TransitTimetable,
        scope: PlaceSuggestionScope,
        stationTimetableLine: String? = nil,
        stationTimetableMunicipality: TransitStationTimetableMunicipality? = nil,
        client: any TransitDataSource,
        onSelection: ((TransitSuggestion) -> Void)? = nil,
        headerShortcutTitle: LocalizedStringKey? = nil,
        showsHeaderShortcut: Bool = false,
        isPerformingHeaderShortcut: Bool = false,
        isHeaderShortcutDisabled: Bool = false,
        headerShortcutAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.prompt = prompt
        _text = text
        self.selection = selection
        self.timetable = timetable
        suggestionScope = scope
        self.stationTimetableLine = stationTimetableLine
        self.stationTimetableMunicipality = stationTimetableMunicipality
        self.onSelection = onSelection
        self.headerShortcutTitle = headerShortcutTitle
        self.showsHeaderShortcut = showsHeaderShortcut
        self.isPerformingHeaderShortcut = isPerformingHeaderShortcut
        self.isHeaderShortcutDisabled = isHeaderShortcutDisabled
        self.headerShortcutAction = headerShortcutAction
        _model = StateObject(wrappedValue: PlaceSuggestionsModel(client: client, scope: scope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldHeader

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: text) { value in
                    if let selectedPlace = selection?.wrappedValue,
                       selectedPlace.text != value {
                        selection?.wrappedValue = nil
                    }
                    model.update(
                        query: value,
                        timetable: timetable,
                        line: stationTimetableLine,
                        municipality: stationTimetableMunicipality,
                        visibility: placeSuggestionVisibility
                    )
                }
                .onChange(of: timetable) { _ in
                    if selection?.wrappedValue?.isCurrentLocation != true {
                        selection?.wrappedValue = nil
                    }
                    model.update(
                        query: text,
                        timetable: timetable,
                        line: stationTimetableLine,
                        municipality: stationTimetableMunicipality,
                        visibility: placeSuggestionVisibility
                    )
                }
                .onChange(of: stationTimetableLine ?? "") { _ in
                    model.update(
                        query: text,
                        timetable: timetable,
                        line: stationTimetableLine,
                        municipality: stationTimetableMunicipality,
                        visibility: placeSuggestionVisibility
                    )
                }
                .onChange(of: stationTimetableMunicipality) { _ in
                    model.update(
                        query: text,
                        timetable: timetable,
                        line: stationTimetableLine,
                        municipality: stationTimetableMunicipality,
                        visibility: placeSuggestionVisibility
                    )
                }
                .onChange(of: placeSuggestionVisibility) { visibility in
                    model.updateVisibility(visibility)
                }
                .overlay(alignment: .trailing) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 6)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Loading suggestions")
                    }
                }
                .overlay(alignment: .leading) {
                    if let selectedPlace = selection?.wrappedValue,
                       let kind = selectedPlace.kind,
                       selectedPlace.text == text {
                        GeometryReader { geometry in
                            SelectedPlaceTypeMarker(
                                text: text,
                                kind: kind,
                                fieldSize: geometry.size
                            )
                        }
                    }
                }
                .alignmentGuide(.placeInputCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                inputWidth = geometry.size.width
                            }
                            .onChange(of: geometry.size.width) { width in
                                inputWidth = width
                            }
                    }
                }
                .popover(
                    isPresented: showsSuggestions,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    suggestionsList
                        .frame(width: inputWidth)
                }
        }
    }

    @ViewBuilder
    private var fieldHeader: some View {
        if let title {
            if let headerShortcutTitle, let headerShortcutAction {
                SearchFieldHeader(
                    title: title,
                    shortcutTitle: headerShortcutTitle,
                    showsShortcut: showsHeaderShortcut,
                    isPerformingShortcut: isPerformingHeaderShortcut,
                    isShortcutDisabled: isHeaderShortcutDisabled,
                    action: headerShortcutAction
                )
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showsSuggestions: Binding<Bool> {
        Binding(
            get: { isFocused && !model.suggestions.isEmpty },
            set: { isPresented in
                if !isPresented {
                    model.selectedSuggestion()
                }
            }
        )
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, suggestion in
                PlaceSuggestionButton(suggestion: suggestion, scope: suggestionScope) {
                    let selectedText = suggestion.selectedText ?? suggestion.text
                    selection?.wrappedValue = PlaceFieldSelection(suggestion: suggestion)
                    text = selectedText
                    onSelection?(suggestion)
                    model.selectedSuggestion()
                    isFocused = false
                }

                if suggestion.text != model.suggestions.last?.text {
                    Divider()
                }
            }
        }
        .background(.background)
    }
}

/// Keeps a selected place's localized type within the exact bounds of its native input.
struct SelectedPlaceTypeMarker: View {
    let text: String
    let kind: PlaceSuggestionKind
    let fieldSize: CGSize

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
            Text(kind.localizedSuffix)
                .foregroundStyle(.tertiary)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.body)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(
            width: max(0, fieldSize.width),
            height: max(0, fieldSize.height),
            alignment: .leading
        )
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
