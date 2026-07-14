import Foundation
import Kastan

/// Owns a station-board query for either departures or arrivals.
@MainActor
final class DeparturesViewModel: ObservableObject {
    @Published var station = ""
    @Published var timetable = IDOSTimetable.defaultTimetable
    @Published var date = Date()
    @Published var time = Date()
    @Published var isArrival = false
    @Published private(set) var departures: [IDOSDeparture] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    let client: any IDOSClienting

    init(client: any IDOSClienting) {
        self.client = client
    }

    var canSearch: Bool {
        !station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    func search() async {
        let station = station.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !station.isEmpty else {
            errorMessage = AppLocalization.string("Enter a station or stop.")
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let request = IDOSDeparturesRequest(
            timetable: timetable,
            station: station,
            date: IDOSRequestFormatting.date(from: date),
            time: IDOSRequestFormatting.time(from: time),
            isArrival: isArrival
        )

        do {
            departures = Array(try await client.findDepartures(request: request).prefix(20))
        } catch {
            departures = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }
}
