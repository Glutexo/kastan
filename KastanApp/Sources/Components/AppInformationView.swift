import AppKit
import Foundation
import SwiftUI

/// Provides localized, verified destinations for the external services described by the app.
struct AppInformationLinks: Equatable {
    let idosWebsite: URL
    let idosTerms: URL
    let projectWebsite: URL

    init(languageCode: String) {
        let usesCzech = languageCode == "cs"
        idosWebsite = URL(string: usesCzech ? "https://idos.cz/" : "https://idos.cz/en/")!
        idosTerms = URL(
            string: usesCzech
                ? "https://idos.cz/smluvni-podminky/"
                : "https://idos.cz/en/smluvni-podminky/"
        )!
        projectWebsite = URL(string: "https://github.com/Glutexo/kastan")!
    }

    static var localized: Self {
        Self(languageCode: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

/// Presents the installed app artwork wherever Kaštan identifies itself inside the interface.
struct ApplicationIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: ApplicationArtwork.icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Explains Kaštan's relationship to IDOS and links to the source service and project details.
struct AppInformationView: View {
    private let links: AppInformationLinks

    init(links: AppInformationLinks = .localized) {
        self.links = links
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ApplicationIcon(size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Kaštan")
                            .font(.title.bold())
                        Text(versionDescription)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("Independent macOS client for occasional personal IDOS searches.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Data source and limitations", systemImage: "info.circle")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Kaštan retrieves journey information from publicly accessible IDOS web pages. It is not an official IDOS or CHAPS application.")
                    Text("Availability and accuracy are not guaranteed. Confirm important journey details with the carrier.")
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                InformationLink(
                    title: "IDOS website",
                    systemImage: "safari",
                    destination: links.idosWebsite
                )
                InformationLink(
                    title: "IDOS Terms and Conditions",
                    systemImage: "doc.text",
                    destination: links.idosTerms
                )
                InformationLink(
                    title: "Kaštan on GitHub",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: links.projectWebsite
                )
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty
        else {
            return version
        }
        return "\(version) (\(build))"
    }
}

/// Renders one external information destination as a full-width macOS link row.
private struct InformationLink: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in the default web browser")
    }
}
