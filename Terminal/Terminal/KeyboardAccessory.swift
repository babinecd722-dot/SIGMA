import UIKit

/// Sticky Ctrl / Alt state shared between the accessory bar and the
/// terminal input path: tapping Ctrl, then a letter, sends a control
/// byte; Alt sends an ESC prefix (Meta).
final class ModifierState {
    private(set) var ctrl = false
    private(set) var alt = false
    var onChange: () -> Void = {}

    func toggleCtrl() { ctrl.toggle(); alt = false; onChange() }
    func toggleAlt() { alt.toggle(); ctrl = false; onChange() }

    /// Typed-byte chords are applied by TerminalSession.sendUserInput —
    /// it owns the semantic ASCII mapping.

    /// Escape-sequence variant for special keys (arrows etc.) that are
    /// already CSI — Ctrl+arrow → CSI 1;5X, Alt+arrow → CSI 1;3X.
    /// DECCKM application-cursor mode sends SS3 for the bare key
    /// (vim/less/tmux copy-mode rely on it); modified arrows stay CSI.
    func arrow(_ code: String, applicationCursor: Bool = false) -> [UInt8] {
        let seq: String
        switch (ctrl, alt) {
        case (true, _): seq = "\u{1B}[1;5\(code)"
        case (_, true): seq = "\u{1B}[1;3\(code)"
        default: seq = applicationCursor ? "\u{1B}O\(code)" : "\u{1B}[\(code)"
        }
        reset()
        return [UInt8](seq.utf8)
    }

    func reset() {
        guard ctrl || alt else { return }
        ctrl = false
        alt = false
        onChange()
    }
}

/// Terminal keyboard bar: modifier keys, arrows, symbols, hide button.
/// Material adapts to light/dark; flush with the keyboard — no gaps.
final class KeyboardAccessoryView: UIInputView {

    /// Injected by the session so sticky state survives bar rebuilds.
    private(set) var modifiers = ModifierState()
    var onSend: ([UInt8]) -> Void = { _ in }
    /// Hide is wired by the owning coordinator so it resigns the actual
    /// terminal view — a global responder search can hit the wrong tab.
    var onHide: () -> Void = {}
    /// DECCKM lookup, wired per attach — the bar outlives any one
    /// TerminalView, so this always points at the current terminal.
    var applicationCursor: () -> Bool = { false }

    private var ctrlButton: KeyButton?
    private var altButton: KeyButton?
    private let cornerBacking = CAShapeLayer()

    /// One bar per session: recreating the input view on every SwiftUI
    /// diff steals/represents the keyboard — that was the flicker.
    /// Weak-boxed so a closed session's bar can die.
    private static var bars: [UUID: BarBox] = [:]

    private final class BarBox {
        weak var bar: KeyboardAccessoryView?
    }

    static func forSession(_ session: TerminalSession) -> KeyboardAccessoryView {
        if let cached = bars[session.id]?.bar { return cached }
        bars = bars.filter { $0.value.bar != nil }
        let bar = KeyboardAccessoryView()
        bar.bind(modifiers: session.modifiers)
        bar.onSend = { [weak session] bytes in
            session?.send(ArraySlice(bytes))
        }
        let box = BarBox()
        box.bar = bar
        bars[session.id] = box
        return bar
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        accessibilityIdentifier = "keyboardAccessory"
        clipsToBounds = false
        cornerBacking.isHidden = true
        layer.insertSublayer(cornerBacking, at: 0)
        bind(modifiers: modifiers)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Rebinds the shared modifier state — the callback must live on the
    /// instance actually used, not a discarded default.
    func bind(modifiers: ModifierState) {
        self.modifiers = modifiers
        modifiers.onChange = { [weak self] in self?.syncModifiers() }
        syncModifiers()
    }

    /// Match the opaque system keyboard backing, including its rounded
    /// corners. The bar has no horizontally scrolling content.
    static func backdrop(light: Bool) -> UIColor {
        light ? UIColor(white: 0.94, alpha: 1) : UIColor(white: 0.09, alpha: 1)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        backgroundColor = Self.backdrop(light: traitCollection.userInterfaceStyle == .light)
        updateCornerBacking()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerBacking()
    }

    private func updateCornerBacking() {
        // iOS 26 draws the phone keyboard with rounded upper corners in
        // another window. A scene background cannot fill those cutouts.
        // Extend only two passive corner wedges below our own accessory;
        // no system view, mask, keyboard key or hit region is modified.
        guard #available(iOS 26.0, *), traitCollection.userInterfaceIdiom == .phone else {
            cornerBacking.isHidden = true
            return
        }
        let radius: CGFloat = traitCollection.verticalSizeClass == .compact ? 16 : 32
        let width = bounds.width
        guard width > radius * 2, bounds.height > 0 else {
            cornerBacking.isHidden = true
            return
        }
        let k: CGFloat = 0.55228475
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: radius),
                      controlPoint1: CGPoint(x: radius * (1 - k), y: 0),
                      controlPoint2: CGPoint(x: 0, y: radius * (1 - k)))
        path.close()
        path.move(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addCurve(to: CGPoint(x: width, y: radius),
                      controlPoint1: CGPoint(x: width - radius * (1 - k), y: 0),
                      controlPoint2: CGPoint(x: width, y: radius * (1 - k)))
        path.close()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cornerBacking.frame = CGRect(x: 0, y: bounds.height, width: width, height: radius)
        cornerBacking.path = path.cgPath
        cornerBacking.fillColor = backgroundColor?.cgColor
        cornerBacking.contentsScale = traitCollection.displayScale
        cornerBacking.isHidden = false
        CATransaction.commit()
    }

    private func build() {
        backgroundColor = Self.backdrop(light: traitCollection.userInterfaceStyle == .light)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        let more = UIButton(type: .system)
        more.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        more.tintColor = .label
        more.accessibilityLabel = String(localized: "Terminal keys")
        more.accessibilityIdentifier = "terminalKeysMenu"
        more.showsMenuAsPrimaryAction = true
        more.menu = additionalKeys()
        stack.addArrangedSubview(more)
        stack.addArrangedSubview(key("esc", spoken: String(localized: "Escape")) { [weak self] in self?.emit([0x1B]) })
        let ctrl = key("ctrl", spoken: String(localized: "Control")) { [weak self] in self?.modifiers.toggleCtrl(); Haptics.select() }
        ctrlButton = ctrl
        stack.addArrangedSubview(ctrl)
        let alt = key("alt", spoken: String(localized: "Option")) { [weak self] in self?.modifiers.toggleAlt(); Haptics.select() }
        altButton = alt
        stack.addArrangedSubview(alt)
        stack.addArrangedSubview(key("tab", glyph: "arrow.right.to.line", spoken: String(localized: "Tab")) { [weak self] in self?.emit([0x09]) })
        for (name, glyph, code) in [("Arrow left", "chevron.left", "D"), ("Arrow down", "chevron.down", "B"),
                                    ("Arrow up", "chevron.up", "A"), ("Arrow right", "chevron.right", "C")] {
            stack.addArrangedSubview(key(code, glyph: glyph, spoken: NSLocalizedString(name, comment: "Terminal arrow")) { [weak self] in self?.emitArrow(code) })
        }
    }

    private func additionalKeys() -> UIMenu {
        func action(_ title: String, glyph: String, perform: @escaping (KeyboardAccessoryView) -> Void) -> UIAction {
            UIAction(title: NSLocalizedString(title, comment: "Terminal key"), image: UIImage(systemName: glyph)) { [weak self] _ in
                guard let self else { return }
                perform(self)
            }
        }
        let movement = UIMenu(options: .displayInline, children: [
            action("Home", glyph: "arrow.left.to.line") { $0.emitArrow("H") },
            action("End", glyph: "arrow.right.to.line") { $0.emitArrow("F") },
            action("Page Up", glyph: "arrow.up.doc") { $0.emitCSI(5) },
            action("Page Down", glyph: "arrow.down.doc") { $0.emitCSI(6) },
            action("Insert", glyph: "text.insert") { $0.emitCSI(2) },
            action("Delete", glyph: "delete.forward") { $0.emitCSI(3) }
        ])
        let functionKeys = UIMenu(title: String(localized: "Function keys"), image: UIImage(systemName: "function"), children: (1...12).map { number in
            UIAction(title: "F\(number)") { [weak self] _ in self?.emitFunction(number) }
        })
        return UIMenu(children: [movement, functionKeys,
            action("Hide keyboard", glyph: "keyboard.chevron.compact.down") { $0.onHide() }
        ])
    }

    private func emitCSI(_ number: Int) {
        let modifier = modifiers.ctrl ? ";5" : modifiers.alt ? ";3" : ""
        emit(Array("\u{1B}[\(number)\(modifier)~".utf8))
    }

    private func emitFunction(_ number: Int) {
        guard (1...12).contains(number) else { return }
        if number <= 4 {
            let code = ["P", "Q", "R", "S"][number - 1]
            let prefix = modifiers.ctrl ? "[1;5" : modifiers.alt ? "[1;3" : "O"
            emit(Array("\u{1B}\(prefix)\(code)".utf8))
        } else {
            emitCSI([15, 17, 18, 19, 20, 21, 23, 24][number - 5])
        }
    }

    private func key(_ title: String, glyph: String? = nil, spoken: String? = nil, action: @escaping () -> Void) -> KeyButton {
        let button = KeyButton(title: title, glyph: glyph)
        button.onTap = action
        button.isAccessibilityElement = true
        button.accessibilityTraits.insert(.button)
        button.accessibilityLabel = spoken ?? title
        return button
    }

    private func syncModifiers() {
        ctrlButton?.isToggled = modifiers.ctrl
        altButton?.isToggled = modifiers.alt
    }

    private func emit(_ bytes: [UInt8]) {
        modifiers.reset()
        onSend(bytes)
    }

    private func emitArrow(_ code: String) {
        onSend(modifiers.arrow(code, applicationCursor: applicationCursor()))
    }
}

/// A single accessory key — keycap chip, adapts to light/dark.
final class KeyButton: UIControl {
    var onTap: () -> Void = {}
    var isToggled = false {
        didSet { updateStyle() }
    }

    private static let fill = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.white.withAlphaComponent(0.85)
    }
    private static let fillPressed = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.28)
            : UIColor.white.withAlphaComponent(0.45)
    }

    init(title: String, glyph: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Self.fill
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)

        if let glyph, let image = UIImage(systemName: glyph) {
            let imageView = UIImageView(image: image)
            imageView.tintColor = .label
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isUserInteractionEnabled = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.heightAnchor.constraint(equalToConstant: 15)
            ])
        } else {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textColor = .label
            label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            label.textAlignment = .center
            label.text = title
            label.isUserInteractionEnabled = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36)
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.08) { self.updateStyle() }
        }
    }

    private func updateStyle() {
        if isToggled {
            backgroundColor = UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.4)
        } else {
            backgroundColor = isHighlighted ? Self.fillPressed : Self.fill
        }
    }

    @objc private func tapped() {
        onTap()
    }
}
