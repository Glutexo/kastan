import AppKit
import SwiftUI

/// Selects the native presentation that can reliably replace an Option-modified action for its location.
enum OptionAlternateButtonPlacement: Equatable {
    case menu
    case toolbar

    /// Menus preserve both native items; visible toolbar controls instead redraw one monitored button.
    var usesNativeAlternateWhenAvailable: Bool {
        self == .menu
    }

    /// A single toolbar item keeps the wider of both labels so neighboring actions remain stationary.
    var reservesAlternateLabelWidth: Bool {
        self == .toolbar
    }
}

/// Keeps a live toolbar action as wide as either presentation without fixed pixel sizing.
struct OptionAlternateButtonLabel<Action, Label: View>: View {
    let primaryAction: Action
    let alternateAction: Action
    let presentedAction: Action
    let reservesAlternateWidth: Bool
    let label: (Action) -> Label

    @ViewBuilder
    var body: some View {
        if reservesAlternateWidth {
            ZStack {
                label(primaryAction)
                    .hidden()
                    .accessibilityHidden(true)
                label(alternateAction)
                    .hidden()
                    .accessibilityHidden(true)
                label(presentedAction)
            }
        } else {
            label(presentedAction)
        }
    }
}

/// Presents one primary action and replaces it with its documented alternate while Option is held.
struct OptionAlternateButton<Action, Label: View>: View {
    @State private var optionIsPressed = NSEvent.modifierFlags.contains(.option)
    let placement: OptionAlternateButtonPlacement
    let primaryAction: Action
    let alternateAction: Action
    let title: (Action) -> LocalizedStringKey
    let isEnabled: (Action) -> Bool
    let perform: (Action) -> Void
    let label: (Action) -> Label

    init(
        placement: OptionAlternateButtonPlacement,
        primaryAction: Action,
        alternateAction: Action,
        title: @escaping (Action) -> LocalizedStringKey,
        isEnabled: @escaping (Action) -> Bool = { _ in true },
        perform: @escaping (Action) -> Void,
        @ViewBuilder label: @escaping (Action) -> Label
    ) {
        self.placement = placement
        self.primaryAction = primaryAction
        self.alternateAction = alternateAction
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *), placement.usesNativeAlternateWhenAvailable {
            button(for: primaryAction)
                .modifierKeyAlternate(.option) {
                    button(for: alternateAction)
                }
        } else {
            monitoredButton(for: optionIsPressed ? alternateAction : primaryAction)
                .background {
                    OptionModifierMonitor(isPressed: $optionIsPressed)
                        .frame(width: 0, height: 0)
                }
        }
    }

    private func button(for action: Action) -> some View {
        Button {
            perform(action)
        } label: {
            presentedLabel(for: action)
        }
        .accessibilityLabel(title(action))
        .help(title(action))
        .disabled(!isEnabled(action))
    }

    /// Resolves modifiers again on activation so the action remains correct between live presentation updates.
    private func monitoredButton(for presentedAction: Action) -> some View {
        Button {
            perform(NSEvent.modifierFlags.contains(.option) ? alternateAction : primaryAction)
        } label: {
            presentedLabel(for: presentedAction)
        }
        .accessibilityLabel(title(presentedAction))
        .help(title(presentedAction))
        .disabled(!isEnabled(presentedAction))
    }

    private func presentedLabel(for action: Action) -> some View {
        OptionAlternateButtonLabel(
            primaryAction: primaryAction,
            alternateAction: alternateAction,
            presentedAction: action,
            reservesAlternateWidth: placement.reservesAlternateLabelWidth,
            label: label
        )
    }
}
