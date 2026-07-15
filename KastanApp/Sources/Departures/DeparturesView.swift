import Kastan
import SwiftUI

/// Presents a compact macOS station-board search workspace and its returned services.
struct DeparturesView: View {
    @ObservedObject var model: DeparturesViewModel
    let client: any IDOSClienting
    @State private var selectedService: ServiceSelection?

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailLayout(availableWidth: geometry.size.width)

            ScrollView {
                page(layout: layout)
                    .frame(width: geometry.size.width, alignment: .topLeading)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .navigationTitle("Departures")
        .sheet(item: $selectedService) { selection in
            ServiceDetailSheet(selection: selection, client: client)
        }
    }

    private func page(layout: DetailLayout) -> some View {
        VStack(spacing: 0) {
            searchPanel(stacked: layout.usesStackedSearchControls)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 18)
                .frame(width: layout.containerWidth, alignment: .topLeading)
                .frame(width: layout.availableWidth, alignment: .topLeading)
                .background(.bar)

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                results
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, 20)
            .frame(width: layout.containerWidth, alignment: .topLeading)
            .frame(width: layout.availableWidth, alignment: .topLeading)
        }
    }

    private func searchPanel(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PlaceAutocompleteField(
                title: "Station",
                prompt: "Station or stop",
                text: $model.station,
                timetable: model.timetable,
                scope: .stations,
                client: client
            )
            .frame(maxWidth: .infinity)

            Divider()

            searchControls(stacked: stacked)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func searchControls(stacked: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 12) {
                timetablePicker
                    .frame(maxWidth: 360)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        datePicker
                        timePicker
                        boardTypePicker
                            .frame(width: 220)
                        Spacer(minLength: 8)
                        searchButton
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            datePicker
                            timePicker
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 12) {
                            boardTypePicker
                                .frame(width: 220)
                            Spacer(minLength: 0)
                            searchButton
                        }
                    }
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                timetablePicker
                    .frame(width: 240)
                datePicker
                timePicker
                boardTypePicker
                    .frame(width: 175)
                Spacer(minLength: 0)
                searchButton
            }
        }
    }

    private var timetablePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timetable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Timetable", selection: $model.timetable.slug) {
                AppTimetablePickerOptions()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .onChange(of: model.timetable.slug) { slug in
                if let timetable = IDOSTimetable.known.first(where: { $0.slug == slug }) {
                    model.timetable = timetable
                }
            }
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Date", selection: $model.date, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Time", selection: $model.time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private var boardTypePicker: some View {
        Picker("Board type", selection: $model.isArrival) {
            Text("Departures").tag(false)
            Text("Arrivals").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var searchButton: some View {
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
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.departures.enumerated()), id: \.element.id) { index, departure in
                    DepartureRow(departure: departure) {
                        let station = departure.stationName ?? model.station
                        selectedService = ServiceSelection(
                            id: departure.id,
                            highlight: model.isArrival
                                ? ServiceRouteHighlight(toStop: station)
                                : ServiceRouteHighlight(fromStop: station)
                        )
                    }

                    if index < model.departures.count - 1 {
                        Divider()
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
                        ResultMetadata.delay(departure.delay)
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
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
