import Foundation
import Kastan

/// Owns one MHD or integrated-transport station-timetable query and its selected route stop.
@MainActor
final class StationTimetablesViewModel: ObservableObject {
    @Published var line = ""
    @Published var from = ""
    @Published var to = ""
    @Published var timetable: IDOSTimetable
    @Published var date = Date()
    @Published var wholeWeek = false
    @Published private(set) var result: IDOSStationTimetable?
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    let client: any IDOSClienting

    init(client: any IDOSClienting) {
        self.client = client
        timetable = Self.defaultTimetable
    }

    var canSearch: Bool {
        [line, from, to].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && !isSearching
    }

    /// Applies both terminal names supplied by IDOS with a selected line direction.
    func selectLineSuggestion(_ suggestion: IDOSSuggestion) {
        line = suggestion.text
        from = suggestion.from ?? ""
        to = suggestion.to ?? ""
        result = nil
        errorMessage = nil
    }

    /// Clears line-specific input when switching to another transport catalog.
    func selectTimetable(slug: String) {
        guard let selected = AppTimetableGroup.stationTimetables.first(where: { $0.slug == slug }),
              selected.slug != timetable.slug
        else {
            return
        }
        timetable = selected
        line = ""
        from = ""
        to = ""
        result = nil
        errorMessage = nil
    }

    func search() async {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !from.isEmpty, !to.isEmpty else {
            errorMessage = AppLocalization.string("Enter a line and both direction stops.")
            return
        }

        isSearching = true
        errorMessage = nil
        result = nil
        defer { isSearching = false }

        let request = IDOSStationTimetableRequest(
            timetable: timetable,
            line: line,
            from: from,
            to: to,
            date: IDOSRequestFormatting.date(from: date),
            wholeWeek: wholeWeek
        )

        do {
            result = try await client.findStationTimetable(
                request: request,
                language: AppLanguagePreference.idosLanguage
            )
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    func selectStop(at index: Int) async {
        guard let result,
              result.stops.indices.contains(index),
              !result.stops[index].isSelected,
              !isSearching
        else {
            return
        }

        if index == result.stops.index(before: result.stops.endIndex) {
            await reverseDirection()
        } else {
            from = result.stops[index].name
            await search()
        }
    }

    func reverseDirection() async {
        guard !isSearching else { return }
        swap(&from, &to)
        await search()
    }

    private static let defaultTimetable = IDOSTimetable.known.first { $0.slug == "pid" }
        ?? IDOSTimetable(slug: "pid", displayName: "Prague + PID")
}
