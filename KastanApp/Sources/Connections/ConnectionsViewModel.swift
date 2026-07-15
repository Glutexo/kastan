import Foundation
import Kastan

/// One independently editable intermediate place in the connection search form.
struct ViaPlaceEntry: Identifiable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

/// Owns one connection search and exposes only UI-ready state to the SwiftUI view.
@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var from = ""
    @Published var to = ""
    @Published var viaPlaces = [ViaPlaceEntry()]
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

    /// Inserts another intermediate-place row directly after the selected row.
    func addViaPlace(after id: ViaPlaceEntry.ID) {
        guard let index = viaPlaces.firstIndex(where: { $0.id == id }) else { return }
        viaPlaces.insert(ViaPlaceEntry(), at: index + 1)
    }

    /// Removes the selected row while retaining one empty row for future input.
    func removeViaPlace(id: ViaPlaceEntry.ID) {
        guard let index = viaPlaces.firstIndex(where: { $0.id == id }) else { return }
        if viaPlaces.count == 1 {
            viaPlaces[0].name = ""
        } else {
            viaPlaces.remove(at: index)
        }
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

        let requestedViaPlaces = viaPlaces
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let request = IDOSConnectionRequest(
            timetable: timetable,
            from: departure,
            to: arrival,
            date: IDOSRequestFormatting.date(from: date),
            time: IDOSRequestFormatting.time(from: time),
            isArrival: isArrival,
            onlyDirect: onlyDirect,
            via: requestedViaPlaces,
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
