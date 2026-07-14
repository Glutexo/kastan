import Kastan
import SwiftUI

/// Loads a service lazily when the user opens its complete route.
@MainActor
final class ServiceDetailViewModel: ObservableObject {
    @Published private(set) var service: IDOSServiceDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let id: String
    private let client: any IDOSClienting

    init(id: String, client: any IDOSClienting) {
        self.id = id
        self.client = client
    }

    func load() async {
        guard service == nil, !isLoading else {
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            service = try await client.serviceDetail(id: id, language: AppLanguagePreference.idosLanguage)
        } catch {
            errorMessage = AppErrorPresentation.message(for: error)
        }
    }
}

/// Identifies a selected service independently of the result type that supplied it.
struct ServiceSelection: Identifiable {
    let id: String
}

/// Shows every stop and piece of service information supplied by IDOS.
struct ServiceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ServiceDetailViewModel

    init(id: String, client: any IDOSClienting) {
        _model = StateObject(wrappedValue: ServiceDetailViewModel(id: id, client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Service route")
                    .font(.title2.bold())
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Group {
                if model.isLoading {
                    ProgressView("Loading service route…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = model.errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Service route unavailable")
                            .font(.title3.bold())
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let service = model.service {
                    serviceContent(service)
                } else {
                    Color.clear
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .task {
            await model.load()
        }
    }

    private func serviceContent(_ service: IDOSServiceDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let color = Color(idosHTMLColor: service.color) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 12, height: 12)
                            }
                            Text([service.transportMode?.emoji, service.name].compactMap { $0 }.joined(separator: " "))
                                .font(.title.bold())
                        }
                        if let date = service.date {
                            Text(date)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let value = service.shareURL, let url = URL(string: value) {
                        Link(destination: url) {
                            Label("Open in IDOS", systemImage: "arrow.up.right.square")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(service.stops.enumerated()), id: \.offset) { index, stop in
                        ServiceStopRow(
                            stop: stop,
                            isFirst: index == 0,
                            isLast: index == service.stops.count - 1
                        )
                    }
                }

                if !service.information.isEmpty {
                    GroupBox("Service information") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(service.information, id: \.self) { information in
                                Text(information)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct ServiceStopRow: View {
    let stop: IDOSServiceStop
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.accentColor)
                    .frame(width: 2, height: 10)
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Circle().fill(.background))
                    .frame(width: 14, height: 14)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.accentColor)
                    .frame(width: 2, height: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stop.name)
                        .font(.headline)
                    Spacer()
                    Text(stopTimes)
                        .font(.body.monospacedDigit())
                }

                if let metadata = ResultMetadata.joined(
                    ResultMetadata.station(tariffZone: stop.tariffZone, platform: stop.platform),
                    stop.track.map { AppLocalization.string("Track %@", $0) },
                    stop.distance
                ) {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(stop.notes, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var stopTimes: String {
        switch (stop.arrivalTime, stop.departureTime) {
        case let (arrival?, departure?) where arrival != departure:
            return "\(arrival) / \(departure)"
        case let (arrival?, _):
            return arrival
        case let (_, departure?):
            return departure
        default:
            return ""
        }
    }
}
