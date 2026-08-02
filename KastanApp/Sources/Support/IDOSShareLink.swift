import AppKit
import SwiftUI

/// Keeps permanent IDOS links in the native macOS sharing workflow while offering direct website opening there.
struct IDOSShareLink<Label: View>: View {
    private let immediateURL: URL?
    private let resolveURL: (@MainActor () async -> URL?)?
    private let label: () -> Label

    /// Presents an already available permanent link without delaying the sharing picker.
    init(item: URL, @ViewBuilder label: @escaping () -> Label) {
        immediateURL = item
        resolveURL = nil
        self.label = label
    }

    /// Resolves service links only after the passenger explicitly opens their sharing picker.
    init(
        resolving resolveURL: @escaping @MainActor () async -> URL?,
        @ViewBuilder label: @escaping () -> Label
    ) {
        immediateURL = nil
        self.resolveURL = resolveURL
        self.label = label
    }

    var body: some View {
        Button(action: presentSharingPicker, label: label)
    }

    private func presentSharingPicker() {
        if let immediateURL {
            IDOSSharingServicePickerPresenter.shared.show(immediateURL)
            return
        }

        guard let resolveURL else { return }
        Task { @MainActor in
            if let url = await resolveURL() {
                IDOSSharingServicePickerPresenter.shared.show(url)
            }
        }
    }
}

/// Adds Kaštan's website-opening action without changing or reordering the system-proposed sharing services.
@MainActor
final class IDOSSharingServicePickerPresenter: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    static let shared = IDOSSharingServicePickerPresenter()

    private let openURL: @MainActor (URL) -> Void
    private var activePicker: NSSharingServicePicker?

    init(openURL: @escaping @MainActor (URL) -> Void = { url in
        _ = NSWorkspace.shared.open(url)
    }) {
        self.openURL = openURL
        super.init()
    }

    /// Anchors the share presentation to the active result window for toolbar, menu, and contextual actions alike.
    func show(_ url: URL) {
        guard let sourceView = (NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow)?.contentView
        else { return }

        activePicker?.close()

        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        activePicker = picker
        picker.show(
            relativeTo: Self.anchorRect(in: sourceView),
            of: sourceView,
            preferredEdge: .minY
        )
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        guard let url = items.lazy.compactMap(Self.url(from:)).first else {
            return proposedServices
        }

        return proposedServices + [openInIDOSService(for: url)]
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        guard activePicker === sharingServicePicker else { return }
        activePicker = nil
    }

    /// Creates a regular sharing-service row so direct opening remains visually consistent with macOS services.
    private func openInIDOSService(for url: URL) -> NSSharingService {
        let title = AppLocalization.string("Open in IDOS")
        let image = NSImage(
            systemSymbolName: "arrow.up.right.square",
            accessibilityDescription: title
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        let service = NSSharingService(
            title: title,
            image: image,
            alternateImage: nil
        ) { [openURL] in
            openURL(url)
        }
        service.menuItemTitle = title
        return service
    }

    private static func url(from item: Any) -> URL? {
        if let url = item as? URL {
            return url
        }
        return (item as? NSURL).map { $0 as URL }
    }

    /// Uses the initiating pointer position when possible and a stable top-center window anchor for keyboard commands.
    private static func anchorRect(in view: NSView) -> NSRect {
        let fallback = NSPoint(x: view.bounds.midX, y: view.bounds.maxY)
        guard let event = NSApplication.shared.currentEvent,
              event.window === view.window
        else {
            return NSRect(origin: fallback, size: NSSize(width: 1, height: 1))
        }

        let location = view.convert(event.locationInWindow, from: nil)
        let point = NSPoint(
            x: min(max(location.x, view.bounds.minX), view.bounds.maxX),
            y: min(max(location.y, view.bounds.minY), view.bounds.maxY)
        )
        return NSRect(origin: point, size: NSSize(width: 1, height: 1))
    }
}
