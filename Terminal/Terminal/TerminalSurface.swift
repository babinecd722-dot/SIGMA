import SwiftUI
import SwiftTerm

/// SwiftTerm surface bound to a TerminalSession: bytes in → render,
/// keystrokes out → SSH channel.
struct TerminalSurface: UIViewRepresentable {
    let session: TerminalSession
    var fontSize: Double
    var theme: TerminalTheme
    var accessory: UIView?
    /// Sticky Ctrl/Alt from the accessory bar — applies to typed keys.
    var modifiers: ModifierState?
    /// Inactive tabs must not hold the first responder — a hidden
    /// surface would keep the keyboard up over the visible one.
    var isActive = true

    func makeUIView(context: Context) -> TerminalView {
        let view = AccessibleTerminalView(frame: .zero, options: Self.terminalOptions)
        Self.applyStyle(view, fontSize: fontSize, theme: theme)
        view.terminalDelegate = context.coordinator
        view.inputAccessoryView = accessory
        view.backgroundColor = theme.uiBackground
        context.coordinator.attach(session: session, view: view, modifiers: modifiers)
        context.coordinator.appliedStyle = Coordinator.StyleSignature(fontSize: fontSize, themeID: theme.id)
        return view
    }

    func updateUIView(_ view: TerminalView, context: Context) {
        // Style diffing: re-applying identical colors/font forces a full
        // glyph re-layout — skip when nothing actually changed.
        let signature = Coordinator.StyleSignature(fontSize: fontSize, themeID: theme.id)
        if context.coordinator.appliedStyle != signature {
            Self.applyStyle(view, fontSize: fontSize, theme: theme)
            context.coordinator.appliedStyle = signature
        }
        // reloadInputViews on an unchanged accessory steals/represents
        // the keyboard — only reload when the view actually swapped.
        if view.inputAccessoryView !== accessory {
            view.inputAccessoryView = accessory
            if view.isFirstResponder { view.reloadInputViews() }
        }
        // The bar is shared per session — another surface may have
        // claimed its closures since this view last attached.
        Self.wireAccessory(view, coordinator: context.coordinator)
        if isActive {
            // A sibling surface (a pushed sheet) may have stolen the
            // output handler — the visible workspace view claims it
            // back so the tab never freezes behind a dismissed sheet.
            if !session.isOutputOwner(view) {
                context.coordinator.claimOutput(on: view)
            }
            // This tab resigned only because it was hidden — switching
            // back brings the keyboard up again without a second tap.
            if context.coordinator.wasFirstResponderOnDeactivate {
                context.coordinator.wasFirstResponderOnDeactivate = false
                _ = view.becomeFirstResponder()
            }
        } else if view.isFirstResponder {
            context.coordinator.wasFirstResponderOnDeactivate = true
            _ = view.resignFirstResponder()
        }
        context.coordinator.modifiers = modifiers
    }

    static func dismantleUIView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    static func applyStyle(_ view: TerminalView, fontSize: Double, theme: TerminalTheme) {
        // A color change must not reset font metrics, selection or PTY size.
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if view.font != font {
            view.font = font
        }
        let style: UIUserInterfaceStyle = theme.id == "paper" ? .light : .dark
        view.overrideUserInterfaceStyle = style
        let keyboardAppearance: UIKeyboardAppearance = style == .light ? .light : .dark
        let keyboardChanged = view.keyboardAppearance != keyboardAppearance
        view.keyboardAppearance = keyboardAppearance
        view.indicatorStyle = style == .light ? .black : .white
        view.inputAccessoryView?.overrideUserInterfaceStyle = style
        view.backgroundColor = theme.uiBackground
        view.nativeBackgroundColor = theme.uiBackground
        view.nativeForegroundColor = theme.uiForeground
        view.caretColor = theme.uiCursor
        // Block-cursor glyphs are legible only against the background.
        view.caretTextColor = theme.uiBackground
        // Theme selection tint — the default teal ignored the palette.
        view.selectedTextBackgroundColor = UIColor(theme.selection)
        view.selectedTextForegroundColor = theme.uiForeground
        view.installColors(theme.ansiColors)
        // tmux and adaptive TUIs query/subscribe to the terminal's
        // light/dark preference independently of UIKit appearance.
        view.updateColorScheme(style == .light ? .light : .dark)
        view.setNeedsDisplay()
        if keyboardChanged, view.isFirstResponder { view.reloadInputViews() }
    }

    /// Desktop SwiftTerm permits 65 MiB per OSC. Keep the mobile parser
    /// bounded before base64 decoding, while allowing clipboard traffic
    /// and inline images up to roughly 6 MiB of encoded content.
    static var terminalOptions: TerminalOptions {
        var options = TerminalOptions.default
        options.maximumOscBytes = 8 * 1024 * 1024
        return options
    }

    /// The accessory bar outlives any single TerminalView (it's cached
    /// per session), so its closures are re-pointed at THIS view every
    /// time they're attached — a stale capture would hide the wrong
    /// keyboard or read a dead terminal's cursor mode.
    private static func wireAccessory(_ view: TerminalView, coordinator: Coordinator) {
        guard let bar = view.inputAccessoryView as? KeyboardAccessoryView else { return }
        bar.overrideUserInterfaceStyle = view.overrideUserInterfaceStyle
        bar.onHide = { [weak view, weak coordinator] in
            // An explicit hide is not a tab-switch resign — don't
            // resurrect the keyboard on the next activation.
            coordinator?.wasFirstResponderOnDeactivate = false
            _ = view?.resignFirstResponder()
            view?.window?.endEditing(true)
        }
        bar.applicationCursor = { [weak view] in
            view?.terminalInputStateSnapshot()?.applicationCursor ?? false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        struct StyleSignature: Equatable {
            let fontSize: Double
            let themeID: String
        }

        private weak var session: TerminalSession?
        private weak var view: TerminalView?
        var modifiers: ModifierState?
        var appliedStyle: StyleSignature?
        /// Set when the surface resigned first responder only because
        /// its tab was hidden — reactivation restores the keyboard.
        var wasFirstResponderOnDeactivate = false
        private var lastBell = Date.distantPast

        func attach(session: TerminalSession, view: TerminalView, modifiers: ModifierState?) {
            self.session = session
            self.view = view
            self.modifiers = modifiers
            (view as? AccessibleTerminalView)?.onProtocolResponse = { [weak session] bytes in
                // Terminal protocol replies must bypass sticky Ctrl/Alt
                // and the line-ending normalization for typed text.
                session?.send(bytes[...])
            }
            claimOutput(on: view)
            // Hide/cursor-mode target THIS terminal — re-wired on every
            // attach because the cached bar may point at an old view.
            TerminalSurface.wireAccessory(view, coordinator: self)
            // Swipe-to-dismiss on the terminal's scroll view.
            view.keyboardDismissMode = .interactive
        }

        /// The view takes ownership of the output handler — any bytes
        /// buffered while a sibling surface held it replay on claim.
        func claimOutput(on view: TerminalView) {
            session?.attachOutput(owner: view) { [weak view] bytes in
                view?.feed(byteArray: bytes)
            }
        }

        func detach() {
            (view as? AccessibleTerminalView)?.onProtocolResponse = nil
            if let view {
                session?.detachOutput(owner: view)
            }
            session = nil
        }

        // MARK: TerminalViewDelegate

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            session?.setSize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            session?.title = title.isEmpty ? (session?.profile.displayName ?? "") : title
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            // Semantic Ctrl/Alt + CR-normalization live in the session.
            session?.sendUserInput(Array(data))
        }

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), url.scheme == "http" || url.scheme == "https" else { return }
            UIApplication.shared.open(url)
        }

        func bell(source: TerminalView) {
            // A runaway `yes | xargs -I{} printf '\a'` must not hammer
            // the haptic engine — coalesce to 2 Hz.
            let now = Date()
            guard now.timeIntervalSince(lastBell) > 0.5 else { return }
            lastBell = now
            Haptics.bell()
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            session?.clipboardWrite(content)
        }

        /// Remote clipboard reads are denied — an untrusted server must
        /// never be able to pull the user's pasteboard silently.
        func clipboardRead(source: TerminalView) -> Data? { nil }

        func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities {
            .standard
        }

        func kittyClipboardAvailableMimeTypes(source: TerminalView, location: KittyClipboardLocation) -> [String]? {
            nil
        }

        func kittyClipboardRead(source: TerminalView, location: KittyClipboardLocation, mimeType: String) -> KittyClipboardReadResult? {
            nil
        }

        func kittyClipboardWrite(source: TerminalView, location: KittyClipboardLocation, content: KittyClipboardWriteContent) -> KittyClipboardWriteResult {
            .unsupported
        }

        func kittyClipboardRequestPermission(source: TerminalView, request: KittyClipboardPermissionRequest) -> KittyClipboardPermissionResult {
            .deny
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

/// VoiceOver reads the current viewport on demand, without copying
/// scrollback on each output packet or publishing it outside the view.
final class AccessibleTerminalView: TerminalView {
    var onProtocolResponse: (@MainActor ([UInt8]) -> Void)?

    nonisolated override func send(source: SwiftTerm.Terminal, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        DispatchQueue.main.async { [weak self] in
            self?.onProtocolResponse?(bytes)
        }
    }

    override func accessibilityActivate() -> Bool {
        becomeFirstResponder()
    }

    override var accessibilityValue: String? {
        get { visibleRowsText(0..<terminalDimensions.rows).joined(separator: "\n") }
        set { }
    }
}
