import AppKit
import SwiftUI

/// Identifies the result-list edge crossed far enough to request another chronological page.
enum SearchResultPagingEdge: Equatable {
    case earlier
    case later
}

/// Normalizes AppKit's flipped and unflipped scroll coordinates into distances beyond each chronological edge.
struct SearchResultScrollMetrics: Equatable {
    let earlierDistance: CGFloat
    let laterDistance: CGFloat
    let contentIsScrollable: Bool

    init(visibleBounds: CGRect, documentFrame: CGRect, documentIsFlipped: Bool) {
        let minimumOffset = documentFrame.minY
        let maximumOffset = max(documentFrame.maxY - visibleBounds.height, minimumOffset)

        if documentIsFlipped {
            earlierDistance = max(minimumOffset - visibleBounds.minY, 0)
            laterDistance = max(visibleBounds.minY - maximumOffset, 0)
        } else {
            earlierDistance = max(visibleBounds.minY - maximumOffset, 0)
            laterDistance = max(minimumOffset - visibleBounds.minY, 0)
        }
        contentIsScrollable = documentFrame.height > visibleBounds.height + 1
    }
}

/// Converts elastic scroll distance into one load per pull-and-release gesture.
struct SearchResultPullTrigger {
    static let activationDistance: CGFloat = 48
    private static let releaseDistance: CGFloat = 4

    private var didTriggerEarlier = false
    private var didTriggerLater = false

    mutating func edgeToLoad(
        metrics: SearchResultScrollMetrics,
        canLoadEarlier: Bool,
        canLoadLater: Bool,
        isLoadingEarlier: Bool,
        isLoadingLater: Bool
    ) -> SearchResultPagingEdge? {
        if metrics.earlierDistance <= Self.releaseDistance, !isLoadingEarlier {
            didTriggerEarlier = false
        }
        if metrics.laterDistance <= Self.releaseDistance, !isLoadingLater {
            didTriggerLater = false
        }

        guard metrics.contentIsScrollable else { return nil }

        if canLoadEarlier,
           !isLoadingEarlier,
           !didTriggerEarlier,
           metrics.earlierDistance >= Self.activationDistance
        {
            didTriggerEarlier = true
            return .earlier
        }
        if canLoadLater,
           !isLoadingLater,
           !didTriggerLater,
           metrics.laterDistance >= Self.activationDistance
        {
            didTriggerLater = true
            return .later
        }
        return nil
    }
}

/// Observes the native elastic scroll offset that SwiftUI geometry does not expose reliably on macOS.
struct SearchResultPullMonitor: NSViewRepresentable {
    let canLoadEarlier: Bool
    let canLoadLater: Bool
    let isLoadingEarlier: Bool
    let isLoadingLater: Bool
    let load: @MainActor (SearchResultPagingEdge) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AttachmentView, context: Context) {
        context.coordinator.update(configuration: self)
        context.coordinator.attach(to: nsView.enclosingScrollView)
    }

    static func dismantleNSView(_ nsView: AttachmentView, coordinator: Coordinator) {
        nsView.coordinator = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var scrollView: NSScrollView?
        private var trigger = SearchResultPullTrigger()
        private var configuration: SearchResultPullMonitor

        init(configuration: SearchResultPullMonitor) {
            self.configuration = configuration
        }

        func update(configuration: SearchResultPullMonitor) {
            self.configuration = configuration
            evaluateCurrentPosition()
        }

        func attach(to scrollView: NSScrollView?) {
            guard self.scrollView !== scrollView else {
                evaluateCurrentPosition()
                return
            }

            detach()
            guard let scrollView else { return }

            self.scrollView = scrollView
            scrollView.verticalScrollElasticity = .allowed
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            evaluateCurrentPosition()
        }

        func detach() {
            guard let scrollView else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            self.scrollView = nil
        }

        func evaluateCurrentPosition() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let metrics = SearchResultScrollMetrics(
                visibleBounds: scrollView.contentView.bounds,
                documentFrame: documentView.frame,
                documentIsFlipped: documentView.isFlipped
            )
            guard let edge = trigger.edgeToLoad(
                metrics: metrics,
                canLoadEarlier: configuration.canLoadEarlier,
                canLoadLater: configuration.canLoadLater,
                isLoadingEarlier: configuration.isLoadingEarlier,
                isLoadingLater: configuration.isLoadingLater
            ) else {
                return
            }
            configuration.load(edge)
        }

        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            evaluateCurrentPosition()
        }
    }

    @MainActor
    final class AttachmentView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            coordinator?.attach(to: enclosingScrollView)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: enclosingScrollView)
        }
    }
}
