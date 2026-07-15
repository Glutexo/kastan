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

/// Distinguishes general IDOS places from station-only station-board inputs.
enum PlaceSuggestionScope {
    case places
    case stations
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

    func update(query: String, timetable: IDOSTimetable) {
        task?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        latestQuery = query

        guard query.count >= 2 else {
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
                let suggestions = switch self.scope {
                case .places:
                    try await self.client.suggest(prefix: query, limit: 6, timetable: timetable)
                case .stations:
                    try await self.client.searchStations(prefix: query, limit: 6, timetable: timetable)
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

/// Converts raw IDOS suggestion metadata into a localized, deduplicated app row.
struct PlaceSuggestionPresentation: Equatable {
    let emoji: String
    let detail: String?

    init(suggestion: IDOSSuggestion) {
        let rawDescription = suggestion.description ?? ""
        emoji = Self.emoji(for: rawDescription)

        var components = rawDescription
            .split(separator: ",")
            .map { Self.localizedComponent(String($0)) }
            .filter { !$0.isEmpty }

        if let region = suggestion.region?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
            components.append(Self.localizedComponent(region))
        }

        var uniqueComponents: [String] = []
        for component in components where !uniqueComponents.contains(where: {
            $0.compare(component, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            uniqueComponents.append(component)
        }

        detail = uniqueComponents.isEmpty ? nil : uniqueComponents.joined(separator: " · ")
    }

    private static func emoji(for description: String) -> String {
        let value = description.lowercased()
        if value.contains("trains") || value.contains("railway") {
            return "🚆"
        }
        if value.contains("buses") || value.contains("bus") {
            return "🚌"
        }
        if value.contains("urban public transport") || value.contains(", pt") {
            return "🚋"
        }
        if value.contains("stop") {
            return "🚏"
        }
        return "📍"
    }

    private static func localizedComponent(_ component: String) -> String {
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
            return trimmed
        }
    }
}

/// Presents a native text field with IDOS suggestions directly below the current input.
struct PlaceAutocompleteField: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    let timetable: IDOSTimetable

    @StateObject private var model: PlaceSuggestionsModel
    @FocusState private var isFocused: Bool
    @State private var inputWidth: CGFloat = 320

    init(
        title: LocalizedStringKey,
        prompt: LocalizedStringKey,
        text: Binding<String>,
        timetable: IDOSTimetable,
        scope: PlaceSuggestionScope,
        client: any IDOSClienting
    ) {
        self.title = title
        self.prompt = prompt
        _text = text
        self.timetable = timetable
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
                    model.update(query: value, timetable: timetable)
                }
                .onChange(of: timetable.slug) { _ in
                    model.update(query: text, timetable: timetable)
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
                let presentation = PlaceSuggestionPresentation(suggestion: suggestion)

                Button {
                    text = suggestion.text
                    model.selectedSuggestion()
                    isFocused = false
                } label: {
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
                }
                .buttonStyle(.plain)

                if suggestion.text != model.suggestions.last?.text {
                    Divider()
                }
            }
        }
        .background(.background)
    }
}
