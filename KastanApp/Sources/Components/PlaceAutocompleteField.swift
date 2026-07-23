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

/// Routes each autocomplete field to the IDOS catalog matching its product input.
enum PlaceSuggestionScope {
    case places
    case stations
    case stationTimetableLines
    case stationTimetableStops
}

/// Debounces IDOS suggestions so typing does not issue a request for every keystroke.
@MainActor
final class PlaceSuggestionsModel: ObservableObject {
    @Published private(set) var suggestions: [IDOSSuggestion] = []
    @Published private(set) var isLoading = false

    private let client: any IDOSClienting
    private let scope: PlaceSuggestionScope
    private var task: Task<Void, Never>?
    private var latestQuery = ""

    init(client: any IDOSClienting, scope: PlaceSuggestionScope) {
        self.client = client
        self.scope = scope
    }

    deinit {
        task?.cancel()
    }

    func update(query: String, timetable: IDOSTimetable, line: String? = nil) {
        task?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        latestQuery = query

        let minimumLength = scope == .stationTimetableLines ? 1 : 2
        guard query.count >= minimumLength else {
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
                let suggestions: [IDOSSuggestion] = switch self.scope {
                case .places:
                    try await self.client.suggest(prefix: query, limit: 6, timetable: timetable)
                case .stations:
                    try await self.client.searchStations(prefix: query, limit: 6, timetable: timetable)
                case .stationTimetableLines:
                    try await self.client.searchStationTimetableLines(
                        prefix: query,
                        limit: 6,
                        timetable: timetable
                    )
                case .stationTimetableStops:
                    if let line, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try await self.client.searchStationTimetableStops(
                            prefix: query,
                            line: line,
                            limit: 6,
                            timetable: timetable
                        )
                    } else {
                        [IDOSSuggestion]()
                    }
                }
                guard !Task.isCancelled, self.latestQuery == query else {
                    return
                }
                self.suggestions = suggestions
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.latestQuery == query else {
                    return
                }
                self.suggestions = []
                self.isLoading = false
            }
        }
    }

    func selectedSuggestion() {
        task?.cancel()
        suggestions = []
        isLoading = false
    }
}

/// Classifies an exact autocomplete choice for a concise visible identity marker.
enum PlaceSuggestionKind: Equatable {
    case municipality
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
        } else if metadata.contains("trains") || description.localizedCaseInsensitiveContains("railway") {
            self = .train
        } else if metadata.contains("buses") || metadata.contains("bus") {
            self = .bus
        } else if metadata.contains("pt") || metadata.contains("urban public transport") {
            self = .publicTransport
        } else if metadata.contains("stop") || metadata.contains(where: { $0.hasPrefix("stop (") }) {
            self = .stop
        } else if metadata.contains("address") {
            self = .address
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
        case .train:
            "🚆"
        case .bus:
            "🚌"
        case .publicTransport:
            "🚋"
        case .stop:
            "🚏"
        case .address, .station, .place:
            "📍"
        }
    }

    private var localizationKey: String {
        switch self {
        case .municipality:
            "municipality"
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

/// Keeps the exact IDOS object and its user-facing type together while the field remains unchanged.
struct PlaceFieldSelection: Equatable {
    let idosSelection: IDOSPlaceSelection
    let kind: PlaceSuggestionKind

    init(idosSelection: IDOSPlaceSelection, kind: PlaceSuggestionKind) {
        self.idosSelection = idosSelection
        self.kind = kind
    }

    init?(suggestion: IDOSSuggestion) {
        guard let idosSelection = IDOSPlaceSelection(suggestion: suggestion) else {
            return nil
        }
        self.init(
            idosSelection: idosSelection,
            kind: PlaceSuggestionKind(description: suggestion.description)
        )
    }

    var text: String {
        idosSelection.text
    }
}

/// Converts raw IDOS suggestion metadata into a localized, deduplicated app row.
struct PlaceSuggestionPresentation: Equatable {
    let kind: PlaceSuggestionKind
    let emoji: String
    let detail: String?

    init(
        suggestion: IDOSSuggestion,
        countryLanguage: IDOSLanguage = AppLanguagePreference.idosLanguage
    ) {
        let rawDescription = suggestion.description ?? ""
        kind = PlaceSuggestionKind(description: rawDescription)
        emoji = kind.emoji

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

    private static func localizedComponent(
        _ component: String,
        countryLanguage: IDOSLanguage
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

/// Makes the complete visual suggestion row select the represented IDOS place.
struct PlaceSuggestionButton: View {
    let suggestion: IDOSSuggestion
    let action: () -> Void

    var body: some View {
        let presentation = PlaceSuggestionPresentation(suggestion: suggestion)

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
struct PlaceAutocompleteField: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    let selection: Binding<PlaceFieldSelection?>?
    let timetable: IDOSTimetable
    let stationTimetableLine: String?
    let onSelection: ((IDOSSuggestion) -> Void)?

    @StateObject private var model: PlaceSuggestionsModel
    @FocusState private var isFocused: Bool
    @State private var inputWidth: CGFloat = 320

    init(
        title: LocalizedStringKey,
        prompt: LocalizedStringKey,
        text: Binding<String>,
        selection: Binding<PlaceFieldSelection?>? = nil,
        timetable: IDOSTimetable,
        scope: PlaceSuggestionScope,
        stationTimetableLine: String? = nil,
        client: any IDOSClienting,
        onSelection: ((IDOSSuggestion) -> Void)? = nil
    ) {
        self.title = title
        self.prompt = prompt
        _text = text
        self.selection = selection
        self.timetable = timetable
        self.stationTimetableLine = stationTimetableLine
        self.onSelection = onSelection
        _model = StateObject(wrappedValue: PlaceSuggestionsModel(client: client, scope: scope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: text) { value in
                    if let selectedPlace = selection?.wrappedValue,
                       selectedPlace.text != value {
                        selection?.wrappedValue = nil
                    }
                    model.update(query: value, timetable: timetable, line: stationTimetableLine)
                }
                .onChange(of: timetable.slug) { _ in
                    selection?.wrappedValue = nil
                    model.update(query: text, timetable: timetable, line: stationTimetableLine)
                }
                .onChange(of: stationTimetableLine ?? "") { _ in
                    model.update(query: text, timetable: timetable, line: stationTimetableLine)
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
                       selectedPlace.text == text {
                        GeometryReader { geometry in
                            SelectedPlaceTypeMarker(
                                text: text,
                                kind: selectedPlace.kind,
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
                PlaceSuggestionButton(suggestion: suggestion) {
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
