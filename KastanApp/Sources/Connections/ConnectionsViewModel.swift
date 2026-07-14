import Foundation
import Kastan

/// Owns one connection search and exposes only UI-ready state to the SwiftUI view.
@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var from = ""
    @Published var to = ""
    @Published var via = ""
    @Published var timetable = IDOSTimetable.defaultTimetable
    @Published var date = Date()
    @Published var time = Date()
    @Published var isArrival = false
    @Published var onlyDirect = false
    @Published var maximumTransfers = 4
    @Published private(set) var connections: [IDOSConnection] = []
    @Published private(set) var isSearching = false
    @Published private(set) var importingConnectionID: String?
    @Published var errorMessage: String?

    let client: any IDOSClienting
    private let calendarImporter: any CalendarImporting

    init(
        client: any IDOSClienting,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter()
    ) {
        self.client = client
        self.calendarImporter = calendarImporter
    }

    var canSearch: Bool {
        !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSearching
    }

    func swapEndpoints() {
        (from, to) = (to, from)
    }

    func search() async {
        let departure = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let arrival = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !departure.isEmpty, !arrival.isEmpty else {
            errorMessage = AppLocalization.string("Enter both a departure and an arrival place.")
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let viaPlaces = via
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: departure,
            to: arrival,
            date: IDOSRequestFormatting.date(from: date),
            time: IDOSRequestFormatting.time(from: time),
            isArrival: isArrival,
            onlyDirect: onlyDirect,
            via: viaPlaces,
            maxTransfers: onlyDirect ? 0 : maximumTransfers,
            resultLimit: 10
        )

        do {
            connections = try await client.findConnections(request: request)
        } catch {
            connections = []
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }

    func addToCalendar(_ connection: IDOSConnection) async {
        importingConnectionID = connection.id
        errorMessage = nil
        defer { importingConnectionID = nil }

        do {
            let calendar = try await client.connectionCalendar(for: connection, timetable: timetable)
            try calendarImporter.open(calendarText: calendar)
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }
}
