import Kastan
import SwiftUI

/// Combines connection search controls with expandable, product-focused journey cards.
struct ConnectionsView: View {
    @ObservedObject var model: ConnectionsViewModel
    let client: any IDOSClienting
    @State private var selectedService: ServiceSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connections")
                        .font(.largeTitle.bold())
                    Text("Find a public transport journey through IDOS.")
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
        .navigationTitle("Connections")
        .sheet(item: $selectedService) { selection in
            ServiceDetailSheet(id: selection.id, client: client)
        }
    }

    private var searchPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    PlaceAutocompleteField(
                        title: "From",
                        prompt: "Departure place",
                        text: $model.from,
                        timetable: model.timetable,
                        scope: .places,
                        client: client
                    )

                    Button {
                        model.swapEndpoints()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Swap departure and arrival")
                    .padding(.top, 24)

                    PlaceAutocompleteField(
                        title: "To",
                        prompt: "Arrival place",
                        text: $model.to,
                        timetable: model.timetable,
                        scope: .places,
                        client: client
                    )
                }

                HStack(alignment: .bottom, spacing: 12) {
                    timetablePicker

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

                    Picker("Time means", selection: $model.isArrival) {
                        Text("Departure").tag(false)
                        Text("Arrival").tag(true)
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

                DisclosureGroup("Journey options") {
                    HStack(spacing: 18) {
                        TextField("Via places, separated by commas", text: $model.via)
                            .textFieldStyle(.roundedBorder)

                        Toggle("Direct only", isOn: $model.onlyDirect)

                        Stepper(
                            AppLocalization.string("Up to %lld transfers", model.maximumTransfers),
                            value: $model.maximumTransfers,
                            in: 0...10
                        )
                        .disabled(model.onlyDirect)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(8)
        } label: {
            Label("Find a connection", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.headline)
        }
    }

    private var timetablePicker: some View {
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
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching, model.connections.isEmpty {
            ProgressView("Searching connections…")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if model.connections.isEmpty, model.errorMessage == nil {
            EmptyStateView(
                title: "No connections yet",
                systemImage: "arrow.left.arrow.right",
                description: "Enter a route and start a search."
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Results")
                    .font(.title2.bold())

                ForEach(Array(model.connections.enumerated()), id: \.element.id) { index, connection in
                    ConnectionCard(
                        number: index + 1,
                        connection: connection,
                        isImportingCalendar: model.importingConnectionID == connection.id,
                        openService: { selectedService = ServiceSelection(id: $0) },
                        addToCalendar: { Task { await model.addToCalendar(connection) } }
                    )
                }
            }
        }
    }
}

private struct ConnectionCard: View {
    let number: Int
    let connection: IDOSConnection
    let isImportingCalendar: Bool
    let openService: (String) -> Void
    let addToCalendar: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(connection.departureTime) → \(connection.arrivalTime)")
                        .font(.title2.bold().monospacedDigit())
                    Text(connection.duration)
                        .foregroundStyle(.secondary)
                    if connection.legs.count <= 1 {
                        Text("Direct")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Menu {
                        Button {
                            addToCalendar()
                        } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                        if let value = connection.shareURL, let url = URL(string: value) {
                            Link(destination: url) {
                                Label("Open in IDOS", systemImage: "arrow.up.right.square")
                            }
                        }
                    } label: {
                        if isImportingCalendar {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isImportingCalendar)
                }

                HStack {
                    Text(connection.departureStation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(connection.arrivalStation)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if !connection.legs.isEmpty {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(Array(connection.legs.enumerated()), id: \.offset) { index, leg in
                            ConnectionLegRow(leg: leg, openService: openService)
                            if index < connection.legs.count - 1 {
                                Divider()
                                    .padding(.leading, 30)
                            }
                        }
                    }
                }
            }
            .padding(6)
        } label: {
            Text(AppLocalization.string("Connection %lld", number))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConnectionLegRow: View {
    let leg: IDOSConnectionLeg
    let openService: (String) -> Void

    var body: some View {
        Button {
            if let id = leg.id {
                openService(id)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 3) {
                    if let color = Color(idosHTMLColor: leg.color) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: 5, height: 38)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.4))
                            .frame(width: 5, height: 38)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text([leg.transportMode?.emoji, leg.name].compactMap { $0 }.joined(separator: " "))
                            .font(.headline)
                        Spacer()
                        if leg.id != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(leg.departureTime)
                            .font(.body.bold().monospacedDigit())
                        Text(leg.fromStation)
                        Spacer()
                        Text(leg.arrivalTime)
                            .font(.body.bold().monospacedDigit())
                        Text(leg.toStation)
                    }
                    if let metadata = ResultMetadata.joined(
                        leg.carrier,
                        leg.delay,
                        ResultMetadata.station(tariffZone: leg.fromTariffZone, platform: leg.fromPlatform)
                    ) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(leg.id == nil)
    }
}
