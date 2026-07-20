import Kastan
import SwiftUI

/// Presents a compact macOS station-board search workspace and its returned services.
struct DeparturesView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: DeparturesViewModel
    let client: any IDOSClienting
    @State private var isSearchFormCollapsed = false

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailLayout(availableWidth: geometry.size.width)

            SearchWorkspace(
                layout: layout,
                searchVerticalPadding: isSearchFormCollapsed ? 10 : 18,
                canLoadEarlier: model.canLoadEarlier,
                canLoadLater: model.canLoadLater,
                isLoadingEarlier: model.isLoadingEarlier,
                isLoadingLater: model.isLoadingLater,
                loadEarlier: { await model.loadMore(.earlier) },
                loadLater: { await model.loadMore(.later) }
            ) {
                if isSearchFormCollapsed {
                    SearchSummaryBar(
                        summary: searchSummary,
                        systemImage: "list.bullet.rectangle",
                        edit: editSearch
                    )
                    .transition(.opacity)
                } else {
                    searchPanel(stacked: layout.usesStackedSearchControls)
                        .transition(.opacity)
                }
            } resultsContent: {
                resultsPanel
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .animation(.easeInOut(duration: 0.18), value: isSearchFormCollapsed)
        }
    }

    private var resultsPanel: some View {
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
    }

    private func searchPanel(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PlaceAutocompleteField(
                title: "Station",
                prompt: "Station or stop",
                text: $model.station,
                selection: $model.stationSelection,
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

    private func searchControls(stacked: Bool) -> some View {
        JourneySearchControls(
            timetable: $model.timetable,
            date: $model.date,
            time: $model.time,
            isArrival: $model.isArrival,
            modeLabel: "Board type",
            departureLabel: "Departures",
            arrivalLabel: "Arrivals",
            isSearching: model.isSearching,
            canSearch: model.canSearch,
            usesStackedLayout: stacked
        ) {
            performSearch()
        }
    }

    private var searchSummary: SearchSummaryPresentation {
        .station(
            name: model.station,
            timetable: model.timetable.appDisplayName,
            date: IDOSRequestFormatting.date(from: model.date),
            time: IDOSRequestFormatting.time(from: model.time),
            mode: AppLocalization.string(model.isArrival ? "Arrivals" : "Departures")
        )
    }

    private func performSearch() {
        guard model.canSearch else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearchFormCollapsed = true
        }
        Task { await model.search() }
    }

    private func editSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearchFormCollapsed = false
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
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.departures.enumerated()), id: \.element.id) { index, departure in
                    let station = departure.stationName ?? model.station
                    let selection = ServiceSelection(
                        id: departure.id,
                        highlight: model.isArrival
                            ? ServiceRouteHighlight(toStop: station)
                            : ServiceRouteHighlight(fromStop: station)
                    )
                    DepartureRow(
                        departure: departure,
                        selection: selection,
                        client: client
                    ) {
                        openWindow(
                            id: AppWindow.serviceDetail,
                            value: selection
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
    let selection: ServiceSelection
    let client: any IDOSClienting
    let openService: () -> Void
    @State private var suppressesPrimaryAction = false

    var body: some View {
        Button {
            guard !suppressesPrimaryAction else {
                suppressesPrimaryAction = false
                return
            }
            openService()
        } label: {
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
        .forceClickPreview(
            size: ResultPreviewLayout.serviceSize,
            suppressesPrimaryAction: $suppressesPrimaryAction
        ) {
            ServiceDetailView(
                selection: selection,
                client: client,
                presentation: .preview
            )
        }
    }
}
