import SwiftUI

/// An action's own shortcut, matched before the palette's bindings see it.
struct ExtensionShortcutKeys: ViewModifier {
    let screen: ExtensionCommandScreen?
    let selection: Int
    /// What is typed in the actions panel while it is open, whose own rows then take the chord.
    let panelQuery: String?
    let activatePanelRow: (Int) -> Void

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            guard let screen, !press.modifiers.isEmpty else { return .ignored }
            let key = ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: press.key)
            guard let panelQuery else {
                return screen.dispatchShortcut(key: key, modifiers: press.modifiers, at: selection)
                    ? .handled : .ignored
            }
            guard
                let row = screen.panelRow(
                    matching: key, modifiers: press.modifiers, at: selection, query: panelQuery)
            else { return .ignored }
            activatePanelRow(row)
            return .handled
        }
    }
}

/// The footer is the shared `ActionBar`: a toast masks its leading `slotWidth` and takes it over.
struct ExtensionToastFooter: ViewModifier {
    let extensions: ExtensionManager
    let showing: Bool
    let inset: CGFloat
    let slotWidth: CGFloat

    func body(content: Content) -> some View {
        let toast = showing ? extensions.toasts.last : nil
        content
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: toast == nil ? 0 : slotWidth)
                    Color.black
                }
            }
            .overlay(alignment: .leading) {
                if let toast {
                    ZStack(alignment: .leading) {
                        // The masked menu button must not take a click through the gap beside the pill.
                        Color.clear
                            .frame(width: slotWidth)
                            .contentShape(Rectangle())
                        ExtensionToastPill(
                            toast: toast, onAction: { extensions.runToastAction(token: $0) },
                            onDismiss: { extensions.hide(toast: toast.id) }
                        )
                        .id(toast.id)
                        .padding(.leading, inset)
                        .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.2), value: toast?.id)
    }
}

struct ExtensionFormKeys: ViewModifier {
    let field: ExtensionFormField
    let onActivate: () -> Void
    let onSubmit: () -> Void
    @Environment(PaletteState.self) private var palette

    func body(content: Content) -> some View {
        content.onKeyPress(keys: ExtensionFormKey.enterKeys.union([.space]), phases: [.down, .repeat]) { press in
            switch ExtensionFormKey.resolve(
                field: field, key: press.key, modifiers: press.modifiers,
                repeating: press.phase == .repeat, menuOpen: palette.menuOpen,
                composing: palette.isComposing)
            {
            case .activate: onActivate()
            case .submit: onSubmit()
            case .consume: break
            case .ignored: return .ignored
            }
            return .handled
        }
    }
}
