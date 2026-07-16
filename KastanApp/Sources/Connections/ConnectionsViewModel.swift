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
    @Published var maximumTransfers = 4
    @Published private(set) var connections: [IDOSConnection] = []
    @Published private(set) var isSearching = false
    @Published private(set) var importingConnectionID: String?
    @Published private(set) var exportingPDFConnectionID: String?
    @Published var errorMessage: String?

    let client: any IDOSClienting
    private let calendarImporter: any CalendarImporting
    private let pdfExporter: any PDFExporting

    init(
        client: any IDOSClienting,
        calendarImporter: any CalendarImporting = WorkspaceCalendarImporter(),
        pdfExporter: any PDFExporting = WorkspacePDFExporter()
    ) {
        self.client = client
        self.calendarImporter = calendarImporter
        self.pdfExporter = pdfExporter
    }

    var canSearch: Bool {
        !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSearching
    }

    /// Presents zero transfers as the equivalent, clearer direct-only journey constraint.
    var transferLimitLabel: String {
        if maximumTransfers == 0 {
            return AppLocalization.string("Direct only")
        }
        return AppLocalization.plural("Up to %lld transfers", count: maximumTransfers)
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
            onlyDirect: maximumTransfers == 0,
            via: requestedViaPlaces,
            maxTransfers: maximumTransfers,
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

    /// Downloads the native IDOS PDF and lets the user choose its destination through macOS.
    func saveAsPDF(_ connection: IDOSConnection) async {
        exportingPDFConnectionID = connection.id
        errorMessage = nil
        defer { exportingPDFConnectionID = nil }

        do {
            let data = try await client.connectionPDF(
                for: connection,
                timetable: timetable,
                language: AppLanguagePreference.idosLanguage
            )
            try await pdfExporter.save(
                pdfData: data,
                suggestedFileName: PDFExportFileName.connection(
                    from: connection.departureStation,
                    to: connection.arrivalStation
                )
            )
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }
}
