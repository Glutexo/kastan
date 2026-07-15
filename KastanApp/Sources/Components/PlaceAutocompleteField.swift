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

/// Presents a native text field with IDOS suggestions directly below the current input.
struct PlaceAutocompleteField: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    let timetable: IDOSTimetable

    @StateObject private var model: PlaceSuggestionsModel
    @FocusState private var isFocused: Bool

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

            HStack(spacing: 8) {
                TextField(prompt, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: text) { value in
                        model.update(query: value, timetable: timetable)
                    }
                    .onChange(of: timetable.slug) { _ in
                        model.update(query: text, timetable: timetable)
                    }

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .alignmentGuide(.placeInputCenter) { dimensions in
                dimensions[VerticalAlignment.center]
            }

            if isFocused, !model.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            text = suggestion.text
                            model.selectedSuggestion()
                            isFocused = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.text)
                                    .foregroundStyle(.primary)
                                if let detail = ResultMetadata.joined(suggestion.description, suggestion.region) {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                }
                .shadow(radius: 5, y: 2)
            }
        }
    }
}
