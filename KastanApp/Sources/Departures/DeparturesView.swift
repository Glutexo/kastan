import Kastan
import SwiftUI

/// Presents an IDOS station board and opens the complete route for any returned service.
struct DeparturesView: View {
    @ObservedObject var model: DeparturesViewModel
    let client: any IDOSClienting
    @State private var selectedService: ServiceSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Departures and arrivals")
                        .font(.largeTitle.bold())
                    Text("Check a station board and open complete service routes.")
                        .foregroundStyle(.secondary)
                }

                searchPanel

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                results
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Departures")
        .sheet(item: $selectedService) { selection in
            ServiceDetailSheet(id: selection.id, client: client)
        }
    }

    private var searchPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                PlaceAutocompleteField(
                    title: "Station",
                    prompt: "Station or stop",
                    text: $model.station,
                    timetable: model.timetable,
                    scope: .stations,
                    client: client
                )

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Timetable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Timetable", selection: $model.timetable.slug) {
                            ForEach(IDOSTimetable.known, id: \.slug) { timetable in
                                Text(timetable.appDisplayName).tag(timetable.slug)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 220)
                        .onChange(of: model.timetable.slug) { slug in
                            if let timetable = IDOSTimetable.known.first(where: { $0.slug == slug }) {
                                model.timetable = timetable
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("Date", selection: $model.date, displayedComponents: .date)
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("Time", selection: $model.time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    Picker("Board type", selection: $model.isArrival) {
                        Text("Departures").tag(false)
                        Text("Arrivals").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 175)

                    Spacer()

                    Button {
                        Task { await model.search() }
                    } label: {
                        if model.isSearching {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 70)
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                                .frame(width: 70)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSearch)
                }
            }
            .padding(8)
        } label: {
            Label("Station board", systemImage: "list.bullet.rectangle")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching, model.departures.isEmpty {
            ProgressView("Loading station board…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if model.departures.isEmpty, model.errorMessage == nil {
            EmptyStateView(
                title: "No station board yet",
                systemImage: "tram",
                description: "Choose a station and start a search."
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.isArrival ? LocalizedStringKey("Arrivals") : LocalizedStringKey("Departures"))
                    .font(.title2.bold())

                ForEach(model.departures, id: \.id) { departure in
                    DepartureRow(departure: departure) {
                        selectedService = ServiceSelection(id: departure.id)
                    }
                }
            }
        }
    }
}

private struct DepartureRow: View {
    let departure: IDOSDeparture
    let openService: () -> Void

    var body: some View {
        Button(action: openService) {
            HStack(spacing: 14) {
                Text(departure.time)
                    .font(.title3.bold().monospacedDigit())
                    .frame(width: 58, alignment: .leading)

                if let color = Color(idosHTMLColor: departure.lineColor) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 5, height: 38)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text([departure.transportMode?.emoji, departure.lineName].compactMap { $0 }.joined(separator: " "))
                            .font(.headline)
                        Text("→ \(departure.destination)")
                    }
                    if let metadata = ResultMetadata.joined(
                        ResultMetadata.station(tariffZone: departure.tariffZone, platform: departure.platform),
                        departure.via.map { AppLocalization.string("via %@", $0) },
                        departure.carrier,
                        departure.delay
                    ) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
