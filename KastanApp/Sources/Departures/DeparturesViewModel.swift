import Foundation
import Kastan

/// Owns a station-board query for either departures or arrivals.
@MainActor
final class DeparturesViewModel: ObservableObject {
    @Published var station = "" {
        didSet {
            if let stationSelection, stationSelection.text != station {
                self.stationSelection = nil
            }
        }
    }
    /// The selected IDOS station or stop, retained only while its visible text is unchanged.
    @Published var stationSelection: IDOSPlaceSelection?
    @Published var timetable = IDOSTimetable.defaultTimetable {
        didSet {
            guard timetable.slug != oldValue.slug else { return }
            stationSelection = nil
        }
    }
    @Published var date = Date()
    @Published var time = Date()
    @Published var isArrival = false
    @Published private(set) var departures: [IDOSDeparture] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var isLoadingLater = false
    @Published var errorMessage: String?

    let client: any IDOSClienting
    private var resultPage: IDOSDeparturePage?

    init(client: any IDOSClienting) {
        self.client = client
    }

    var canSearch: Bool {
        !station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSearching && !isLoadingEarlier && !isLoadingLater
    }

    var canLoadEarlier: Bool {
        !departures.isEmpty && resultPage?.canLoadEarlier == true && !isSearching && !isLoadingLater
    }

    var canLoadLater: Bool {
        !departures.isEmpty && resultPage?.canLoadLater == true && !isSearching && !isLoadingEarlier
    }

    func search() async {
        let station = station.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !station.isEmpty else {
            errorMessage = AppLocalization.string("Enter a station or stop.")
            return
        }

        isSearching = true
        errorMessage = nil
        resultPage = nil
        defer { isSearching = false }

        let request = IDOSDeparturesRequest(
            timetable: timetable,
            station: station,
            stationSelection: stationSelection?.text == station ? stationSelection : nil,
            date: IDOSRequestFormatting.date(from: date),
            time: IDOSRequestFormatting.time(from: time),
            isArrival: isArrival
        )

        do {
            let page = try await client.findDeparturesPage(request: request)
            departures = page.departures
            resultPage = page
        } catch {
            departures = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    /// Extends the submitted station board at the selected chronological edge without replacing rows.
    func loadMore(_ direction: IDOSPageDirection) async {
        guard let resultPage,
              (direction == .earlier ? canLoadEarlier : canLoadLater)
        else {
            return
        }

        if direction == .earlier {
            isLoadingEarlier = true
        } else {
            isLoadingLater = true
        }
        errorMessage = nil
        defer {
            isLoadingEarlier = false
            isLoadingLater = false
        }

        do {
            let page = try await client.findDeparturesPage(from: resultPage, direction: direction)
            self.resultPage = page
            merge(page.departures, direction: direction)
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    private func merge(_ additionalDepartures: [IDOSDeparture], direction: IDOSPageDirection) {
        let knownIDs = Set(departures.map(\.id))
        let uniqueDepartures = additionalDepartures.filter { !knownIDs.contains($0.id) }
        if direction == .earlier {
            departures.insert(contentsOf: uniqueDepartures, at: 0)
        } else {
            departures.append(contentsOf: uniqueDepartures)
        }
    }
}
