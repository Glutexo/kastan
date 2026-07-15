import Kastan
import SwiftUI

/// Combines a compact macOS search workspace with expandable journey results.
struct ConnectionsView: View {
    @ObservedObject var model: ConnectionsViewModel
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
        .navigationTitle("Connections")
        .sheet(item: $selectedService) { selection in
            ServiceDetailSheet(selection: selection, client: client)
        }
    }

    private func page(layout: DetailLayout) -> some View {
        VStack(spacing: 0) {
            searchPanel(layout: layout)
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

    private func searchPanel(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            endpointControls(stacked: layout.usesStackedEndpoints)

            Divider()

            searchControls(stacked: layout.usesStackedSearchControls)

            journeyOptions(stacked: layout.usesStackedOptions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func endpointControls(stacked: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                fromField
                HStack {
                    Spacer()
                    swapButton
                }
                toField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .placeInputCenter, spacing: 10) {
                fromField
                    .frame(minWidth: 240, maxWidth: .infinity)
                swapButton
                toField
                    .frame(minWidth: 240, maxWidth: .infinity)
            }
        }
    }

    private var fromField: some View {
        PlaceAutocompleteField(
            title: "From",
            prompt: "Departure place",
            text: $model.from,
            timetable: model.timetable,
            scope: .places,
            client: client
        )
    }

    private var toField: some View {
        PlaceAutocompleteField(
            title: "To",
            prompt: "Arrival place",
            text: $model.to,
            timetable: model.timetable,
            scope: .places,
            client: client
        )
    }

    private var swapButton: some View {
        Button {
            model.swapEndpoints()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Swap departure and arrival")
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
                        timeModePicker
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
                            timeModePicker
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
                timeModePicker
                    .frame(width: 175)
                Spacer(minLength: 0)
                searchButton
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

    private var timeModePicker: some View {
        Picker("Time means", selection: $model.isArrival) {
            Text("Departure").tag(false)
            Text("Arrival").tag(true)
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

    private func journeyOptions(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Journey options")
                .padding(.bottom, 8)

            Divider()

            ForEach($model.viaPlaces) { $viaPlace in
                viaPlaceRow(name: $viaPlace.name, id: viaPlace.id)
                    .padding(.vertical, 6)

                Divider()
            }

            journeyConstraintControls(stacked: stacked)
                .padding(.vertical, 8)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func viaPlaceRow(name: Binding<String>, id: ViaPlaceEntry.ID) -> some View {
        HStack(spacing: 8) {
            TextField("Via", text: name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 520)

            Spacer(minLength: 0)

            Button {
                model.removeViaPlace(id: id)
            } label: {
                Label("Remove via place", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 14)
            }
            .buttonStyle(.bordered)
            .help("Remove via place")

            Button {
                model.addViaPlace(after: id)
            } label: {
                Label("Add via place", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 14)
            }
            .buttonStyle(.bordered)
            .help("Add via place")
        }
    }

    @ViewBuilder
    private func journeyConstraintControls(stacked: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                directToggle
                transfersStepper
            }
        } else {
            HStack(spacing: 18) {
                directToggle
                transfersStepper
                Spacer(minLength: 0)
            }
        }
    }

    private var directToggle: some View {
        Toggle("Direct only", isOn: $model.onlyDirect)
    }

    private var transfersStepper: some View {
        Stepper(
            AppLocalization.string("Up to %lld transfers", model.maximumTransfers),
            value: $model.maximumTransfers,
            in: 0...10
        )
        .disabled(model.onlyDirect)
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
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.connections.enumerated()), id: \.element.id) { index, connection in
                    ConnectionCard(
                        number: index + 1,
                        connection: connection,
                        isImportingCalendar: model.importingConnectionID == connection.id,
                        openService: { selectedService = $0 },
                        addToCalendar: { Task { await model.addToCalendar(connection) } }
                    )

                    if index < model.connections.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ConnectionCard: View {
    let number: Int
    let connection: IDOSConnection
    let isImportingCalendar: Bool
    let openService: (ServiceSelection) -> Void
    let addToCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(AppLocalization.string("Connection %lld", number))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(connection.departureStation)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(connection.arrivalStation)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(connection.departureStation)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .foregroundStyle(.secondary)
                        Text(connection.arrivalStation)
                    }
                }
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
        .padding(.vertical, 14)
    }
}

private struct ConnectionLegRow: View {
    let leg: IDOSConnectionLeg
    let openService: (ServiceSelection) -> Void

    var body: some View {
        Button {
            if let id = leg.id {
                openService(
                    ServiceSelection(
                        id: id,
                        highlight: ServiceRouteHighlight(
                            fromStop: leg.fromStation,
                            toStop: leg.toStation
                        )
                    )
                )
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(leg.departureTime)
                                .font(.body.bold().monospacedDigit())
                                .frame(width: 48, alignment: .leading)
                            Text(leg.fromStation)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(leg.arrivalTime)
                                .font(.body.bold().monospacedDigit())
                                .frame(width: 48, alignment: .leading)
                            Text(leg.toStation)
                        }
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
