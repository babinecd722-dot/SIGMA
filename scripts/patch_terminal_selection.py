#!/usr/bin/env python3
"""Native terminal selection and restricted edit menus for pinned SwiftTerm."""
COPY_STATE_PREVIOUS = r"""    private var terminalEditMenuVisible = false
    private var copyHoldGesture: UILongPressGestureRecognizer?

    private func dismissTerminalEditMenu() {
        terminalEditMenuVisible = false
        if #available(iOS 16.0, visionOS 1.0, *) {
            interactions.compactMap { $0 as? UIEditMenuInteraction }
                .forEach { $0.dismissMenu() }
        }
        UIMenuController.shared.hideMenu()
    }

    var lastLongSelect: Position?"""

COPY_STATE = r"""    private var terminalEditMenuVisible = false
    private var copyHoldGesture: UILongPressGestureRecognizer?
    private var copyHoldSelecting = false
    private var selectionHandleDragging = false
    private var selectionHandleTouchOrigin = CGPoint.zero
    private var selectionHandleEndpointOrigin = CGPoint.zero
    private lazy var copySelectionPanDelegate = CopySelectionPanDelegate(terminalView: self)

    @MainActor
    private final class CopySelectionPanDelegate: NSObject, UIGestureRecognizerDelegate {
        private weak var terminalView: TerminalView?
        init(terminalView: TerminalView) { self.terminalView = terminalView }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = terminalView else { return false }
            return view.copySelectionHandle(at: gestureRecognizer.location(in: view)) != nil
        }
    }

    /// Only the native-sized handle targets own a selection pan. A swipe
    /// elsewhere remains a scroll, rather than stretching an old selection.
    func copySelectionHandle(at point: CGPoint) -> Bool? {
        guard hasActiveSelection, point.x.isFinite, point.y.isFinite else { return nil }
        return withTerminal { _ in
            let forward = Position.compare(selection.start, selection.end) != .after
            let start = forward ? selection.start : selection.end
            let end = forward ? selection.end : selection.start
            let startCenter = CGPoint(x: CGFloat(start.col) * cellDimension.width,
                                      y: CGFloat(start.row) * cellDimension.height - 6)
            let endCenter = CGPoint(x: CGFloat(end.col) * cellDimension.width,
                                    y: CGFloat(end.row + 1) * cellDimension.height + 6)
            func distance(_ center: CGPoint) -> CGFloat? {
                guard abs(point.x - center.x) <= 22, abs(point.y - center.y) <= 22 else { return nil }
                return hypot(point.x - center.x, point.y - center.y)
            }
            let a = distance(startCenter), b = distance(endCenter)
            if let a, let b { return a <= b }
            if a != nil { return true }
            if b != nil { return false }
            return nil
        }
    }

    /// The output is selectable, but it is not a password/passkey form.
    /// Use explicit actions for both UIEditMenuInteraction and UIKit's
    /// context-menu builder. Never inherit AutoFill or Writing Tools items.
    func terminalCopyMenu() -> UIMenu {
        if hasActiveSelection {
            return UIMenu(children: [
                UIAction(title: NSLocalizedString("Copy", comment: "Edit action"),
                         image: UIImage(systemName: "doc.on.doc"),
                         identifier: UIAction.Identifier("terminal.copy")) { [weak self] _ in self?.copy(nil) },
                UIAction(title: NSLocalizedString("Select All", comment: "Edit action"),
                         identifier: UIAction.Identifier("terminal.selectAll")) { [weak self] _ in
                    guard let self else { return }
                    self.selectAll(nil)
                    self.presentCopyMenu(at: CGPoint(x: self.bounds.midX, y: self.bounds.midY))
                }
            ])
        }
        return UIMenu(children: [
            UIAction(title: NSLocalizedString("Paste", comment: "Edit action"),
                     image: UIImage(systemName: "doc.on.clipboard"),
                     identifier: UIAction.Identifier("terminal.paste"),
                     attributes: UIPasteboard.general.hasStrings ? [] : .disabled) { [weak self] _ in self?.paste(nil) }
        ])
    }

    open override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        builder.replaceChildren(ofMenu: .root) { [weak self] _ in
            self?.terminalCopyMenu().children ?? []
        }
    }

    private func dismissTerminalEditMenu() {
        terminalEditMenuVisible = false
        if #available(iOS 16.0, visionOS 1.0, *) {
            interactions.compactMap { $0 as? UIEditMenuInteraction }
                .forEach { $0.dismissMenu() }
        }
        UIMenuController.shared.hideMenu()
    }

    var lastLongSelect: Position?"""

COPY_MENU_PREVIOUS = r"""@available(iOS 16.0, visionOS 1.0, *)
extension TerminalView: @preconcurrency UIEditMenuInteractionDelegate {
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    menuFor configuration: UIEditMenuConfiguration,
                                    suggestedActions: [UIMenuElement]) -> UIMenu? {
        // Explicit targets allow local selection with the keyboard closed.
        // Making the terminal first responder here would resize/reflow the
        // very text being selected underneath the user's finger.
        var actions: [UIMenuElement] = []
        if hasActiveSelection {
            actions.append(UIAction(title: NSLocalizedString("Copy", comment: "Edit action"),
                                    image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copy(nil)
            })
        }
        actions.append(UIAction(title: NSLocalizedString("Paste", comment: "Edit action"),
                                image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
            self?.paste(nil)
        })
        actions.append(UIAction(title: NSLocalizedString("Select All", comment: "Edit action")) { [weak self] _ in
            guard let self else { return }
            self.selectAll(nil)
            self.showContextMenu(forRegion: self.makeContextMenuRegionForSelection(),
                                 pos: self.lastLongSelect ?? Position(col: 0, row: 0))
        })
        return UIMenu(children: actions)
    }

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    willPresentMenuFor configuration: UIEditMenuConfiguration,
                                    animator: UIEditMenuInteractionAnimating) {
        terminalEditMenuVisible = true
    }

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    willDismissMenuFor configuration: UIEditMenuConfiguration,
                                    animator: UIEditMenuInteractionAnimating) {
        terminalEditMenuVisible = false
    }
}

extension TerminalViewDelegate {"""

COPY_MENU = r"""@available(iOS 16.0, visionOS 1.0, *)
extension TerminalView: @preconcurrency UIEditMenuInteractionDelegate {
    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    menuFor configuration: UIEditMenuConfiguration,
                                    suggestedActions: [UIMenuElement]) -> UIMenu? {
        // Ignore suggested credential/rewriting actions. Output selection
        // and terminal input have deliberately separate menus.
        terminalCopyMenu()
    }

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    willPresentMenuFor configuration: UIEditMenuConfiguration,
                                    animator: UIEditMenuInteractionAnimating) {
        terminalEditMenuVisible = true
    }

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                    willDismissMenuFor configuration: UIEditMenuConfiguration,
                                    animator: UIEditMenuInteractionAnimating) {
        terminalEditMenuVisible = false
    }
}

extension TerminalViewDelegate {"""

COPY_HOLD_PREVIOUS = r"""        guard gestureRecognizer.state == .began else { return }
        selectWordForCopy(at: gestureRecognizer.location(in: self))
    }

    /// A deliberate hold always selects local output, even while
    /// tmux or another TUI has enabled mouse reporting.
    public func selectWordForCopy(at point: CGPoint) {
        let hit = calculateTapHit(point: point).grid
        withTerminal { terminal in
            selection.selectWordOrExpression(at: hit, in: terminal.displayBuffer)
            selection.selectionMode = .character
        }
        enableSelectionPanGesture()
        frameDriver.markDirty()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.hasActiveSelection else { return }
            let region = self.hasActiveSelection ? self.makeContextMenuRegionForSelection()
                : self.makeContextMenuRegionForTap(point: point)
            self.showContextMenu(forRegion: region, pos: hit)
        }
    }"""

COPY_HOLD = r"""        let point = gestureRecognizer.location(in: self)
        switch gestureRecognizer.state {
        case .began:
            selectWordForCopy(at: point)
            copyHoldSelecting = hasActiveSelection
        case .changed:
            guard copyHoldSelecting else { return }
            updateHeldCopySelection(at: point)
        case .ended:
            stopSelectionTimer()
            copyHoldSelecting = false
            presentCopyMenu(at: point)
        case .cancelled, .failed:
            stopSelectionTimer()
            copyHoldSelecting = false
        default:
            break
        }
    }

    /// Select real output without focusing the input or selecting a run of
    /// unused cells. UIScrollView points already include the content offset.
    public func selectWordForCopy(at point: CGPoint) {
        dismissTerminalEditMenu()
        guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { return }
        let hit = calculateTapHit(point: point).grid
        let selected = withTerminal { terminal -> Bool in
            let buffer = terminal.displayBuffer
            selection.selectNone()
            guard hit.row >= 0, hit.row < buffer.lines.count,
                  point.x >= 0, point.x < CGFloat(terminal.cols) * cellDimension.width,
                  point.y >= 0, point.y < CGFloat(buffer.lines.count) * cellDimension.height else {
                return false
            }
            var wordHit = hit
            var cell = buffer.getChar(atBufferRelative: wordHit)
            // A hit on the trailing half of a wide glyph belongs to that
            // glyph; it is not an empty terminal cell.
            if cell.width == 0, wordHit.col > 0 {
                let previous = Position(col: wordHit.col - 1, row: wordHit.row)
                let lead = buffer.getChar(atBufferRelative: previous)
                if lead.width == 2 { wordHit = previous; cell = lead }
            }
            let character = terminal.getCharacter(for: cell)
            guard character != "\0", !character.isWhitespace else { return false }
            selection.selectWordOrExpression(at: wordHit, in: buffer)
            // Keep the seed word while the same held finger drags either
            // way. A later handle drag switches to precise character mode.
            return selection.active
        }
        if selected { enableSelectionPanGesture() }
        else { disableSelectionPanGesture() }
        frameDriver.markDirty()
        guard selected else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.hasActiveSelection else { return }
            self.presentCopyMenu(at: point)
        }
    }

    func presentCopyMenu(at point: CGPoint) {
        guard window != nil, point.x.isFinite, point.y.isFinite else { return }
        let region = hasActiveSelection ? makeContextMenuRegionForSelection()
            : makeContextMenuRegionForTap(point: point)
        showContextMenu(forRegion: region, pos: calculateTapHit(point: point).grid)
    }

    func copySelectionPosition(at point: CGPoint) -> Position {
        let hit = calculateTapHit(point: point).grid
        return withTerminal { terminal in
            Position(col: max(0, min(terminal.cols - 1, hit.col)),
                     row: max(0, min(terminal.displayBuffer.lines.count - 1, hit.row)))
        }
    }

    func updateHeldCopySelection(at point: CGPoint) {
        guard hasActiveSelection, point.x.isFinite, point.y.isFinite else { return }
        dismissTerminalEditMenu()
        let hit = copySelectionPosition(at: point)
        withTerminal { _ in extendHeldCopySelectionLocked(to: hit) }
        updateCopySelectionAutoScroll(at: point)
        requestDisplay()
    }

    func extendHeldCopySelectionLocked(to hit: Position) {
        selection.extendTouchWordSelection(bufferPosition: hit)
    }

    func updateCopySelectionAutoScroll(at point: CGPoint) {
        stopSelectionTimer()
        let distance = point.y - bounds.minY
        guard distance < 0 || distance > bounds.height else { return }
        let direction: CGFloat = distance < 0 ? -1 : 1
        startSelectionTimer { [weak self] in
            guard let self, self.hasActiveSelection else { return }
            let maxOffset = max(0, self.contentSize.height - self.bounds.height)
            let y = min(maxOffset, max(0, self.contentOffset.y + direction * self.cellDimension.height))
            self.setContentOffset(CGPoint(x: self.contentOffset.x, y: y), animated: false)
            let edge = CGPoint(x: point.x, y: y + (direction < 0 ? 0 : self.bounds.height - 1))
            let hit = self.copySelectionPosition(at: edge)
            self.withTerminal { _ in
                if self.selectionHandleDragging { self.selection.pivotExtend(bufferPosition: hit) }
                else { self.extendHeldCopySelectionLocked(to: hit) }
            }
            self.requestDisplay()
        }
    }"""

COPY_PAN_SETUP_PREVIOUS = r"""        self.panSelectionGesture = gesture
        panGestureRecognizer.require(toFail: gesture)
"""

COPY_PAN_SETUP = r"""        gesture.maximumNumberOfTouches = 1
        gesture.delegate = copySelectionPanDelegate
        self.panSelectionGesture = gesture
        panGestureRecognizer.require(toFail: gesture)
"""

COPY_PAN_PREVIOUS = r"""    @objc func panSelectionHandler (_ gestureRecognizer: UIPanGestureRecognizer) {
        func near (_ pos1: Position, _ pos2: Position) -> Bool {
            return abs (pos1.col-pos2.col) < 3 && abs (pos1.row-pos2.row) < 2
        }
        
        switch gestureRecognizer.state {
        case .began:
            let hit = calculateTapHit(gesture: gestureRecognizer).grid
            let extended = withTerminal { _ -> Bool in
                if selection.active {
                    var extend = false
                    if near (selection.start, hit) {
                        selection.pivot = selection.end
                        extend = true
                    } else if near (selection.end, hit) {
                        selection.pivot = selection.start
                        extend = true
                    }
                    if extend {
                        selection.pivotExtend(bufferPosition: hit)
                        return true
                    }
                }
                return false
            }
            if extended {
                requestDisplay()
                break
            }
            panStart = hit
        case .changed:
            let absoluteY = gestureRecognizer.location (in: self).y - contentOffset.y
            let hit = calculateTapHit(gesture: gestureRecognizer).grid
            if withTerminal({ _ in selection.active }) {
                stopSelectionTimer()
                withTerminal { _ in selection.pivotExtend(bufferPosition: hit) }
                gestureRecognizer.setTranslation(CGPoint.zero, in: self)
                if absoluteY < 0 || absoluteY > bounds.height {
                    startSelectionTimer {
                        let newPlace = CGRect (x: 0, y: max (0, self.contentOffset.y+absoluteY), width: self.bounds.width, height: self.bounds.height)
                        self.scrollRectToVisible(newPlace, animated: true)
                    }
                }
                requestDisplay()
            } else {
                if let ps = panStart {
                    let deltaRow = ps.row - hit.row
                    if allowMouseReporting {
                        // TODO: what scenario would have this?
                        scrollDown (lines: deltaRow)
                    } else {
                        let deltaCol = ps.col - hit.col
                        
                        sendKey (deltaCol: deltaCol, deltaRow: deltaRow)
                    }
                }
            }
        case .ended:
            stopSelectionTimer()
            if withTerminal({ _ in selection.active }) {
                showContextMenu (forRegion: makeContextMenuRegionForSelection(), pos: calculateTapHit(gesture: gestureRecognizer).grid)
            }
            break
        case .cancelled:
            stopSelectionTimer()
            withTerminal { _ in selection.active = false }
        default:
            break
        }
    }
    """

COPY_PAN = r"""    @objc func panSelectionHandler (_ gestureRecognizer: UIPanGestureRecognizer) {
        let point = gestureRecognizer.location(in: self)
        switch gestureRecognizer.state {
        case .began:
            selectionHandleDragging = false
            guard let isStart = copySelectionHandle(at: point) else { return }
            selectionHandleDragging = true
            dismissTerminalEditMenu()
            selectionHandleTouchOrigin = point
            withTerminal { _ in
                let forward = Position.compare(selection.start, selection.end) != .after
                let start = forward ? selection.start : selection.end
                let end = forward ? selection.end : selection.start
                let moving = isStart ? start : end
                selection.pivot = isStart ? end : start
                selection.selectionMode = .character
                selectionHandleEndpointOrigin = CGPoint(x: CGFloat(moving.col) * cellDimension.width,
                                                       y: (CGFloat(moving.row) + 0.5) * cellDimension.height)
            }
        case .changed:
            guard selectionHandleDragging else { return }
            let adjusted = CGPoint(x: selectionHandleEndpointOrigin.x + point.x - selectionHandleTouchOrigin.x,
                                   y: selectionHandleEndpointOrigin.y + point.y - selectionHandleTouchOrigin.y)
            let hit = copySelectionPosition(at: adjusted)
            withTerminal { _ in selection.pivotExtend(bufferPosition: hit) }
            updateCopySelectionAutoScroll(at: adjusted)
            requestDisplay()
        case .ended:
            stopSelectionTimer()
            guard selectionHandleDragging else { return }
            selectionHandleDragging = false
            presentCopyMenu(at: point)
        case .cancelled, .failed:
            stopSelectionTimer()
            selectionHandleDragging = false
        default:
            break
        }
    }"""


COPY_TOUCH_VIEW_PREVIOUS = r"""    func extendHeldCopySelectionLocked(to hit: Position) {
        let cell = terminal.displayBuffer.getChar(atBufferRelative: hit)
        let character = terminal.getCharacter(for: cell)
        guard selection.selectionMode == .word,
              character == "\0" || character.isWhitespace,
              let anchor = selection.wordSelectionAnchor else {
            selection.dragExtend(bufferPosition: hit)
            return
        }
        // A finger in trailing space defines an endpoint, not a request
        // to select every blank cell to the edge of the terminal row.
        // Preserve the seed word even when the drag crosses backwards.
        selection.selectionMode = .character
        if Position.compare(hit, anchor.start) == .before {
            selection.start = anchor.end
            selection.dragExtend(bufferPosition: hit)
        } else if Position.compare(hit, anchor.end) == .after {
            selection.start = anchor.start
            selection.dragExtend(bufferPosition: hit)
        } else {
            selection.start = anchor.start
            selection.dragExtend(bufferPosition: anchor.end)
        }
        selection.selectionMode = .word
    }
"""

COPY_TOUCH_VIEW = r"""    func extendHeldCopySelectionLocked(to hit: Position) {
        selection.extendTouchWordSelection(bufferPosition: hit)
    }
"""

COPY_TOUCH_SERVICE = r"""    /// Extend an iOS held-word selection without scanning whitespace
    /// all the way to the last blank cell. Callers hold terminalLock.
    func extendTouchWordSelection(bufferPosition unchecked: Position) {
        let hit = clamp(terminal.displayBuffer, unchecked)
        let cell = terminal.displayBuffer.getChar(atBufferRelative: hit)
        let character = terminal.getCharacter(for: cell)
        guard selectionMode == .word,
              character == "\0" || character.isWhitespace,
              let anchor = wordSelectionAnchor else {
            dragExtend(bufferPosition: hit)
            return
        }
        // Retain the seed word while moving just the touched endpoint.
        // Endpoint mutation stays inside its owning SelectionService.
        selectionMode = .character
        if Position.compare(hit, anchor.start) == .before {
            start = anchor.end
            dragExtend(bufferPosition: hit)
        } else if Position.compare(hit, anchor.end) == .after {
            start = anchor.start
            dragExtend(bufferPosition: hit)
        } else {
            start = anchor.start
            dragExtend(bufferPosition: anchor.end)
        }
        selectionMode = .word
    }

"""


COPY_STANDARD_SELECT_PREVIOUS = r"""    @objc public override func select (_ sender: Any?)  {
        if let loc = lastLongSelect {
            withTerminal { terminal in
                selection.selectWordOrExpression(at: Position (col: loc.col, row: loc.row), in: terminal.displayBuffer)
                selection.selectionMode = .character
            }
            enableSelectionPanGesture()
            DispatchQueue.main.async {
                self.showContextMenu(forRegion:  self.makeContextMenuRegionForSelection(), pos: loc)
            }
@LEGACY_SELECT_BLANK@
        }
        lastLongSelect = nil
    }""".replace("@LEGACY_SELECT_BLANK@", " " * 12)

COPY_STANDARD_SELECT = r"""    @objc public override func select (_ sender: Any?) {
        guard let hit = lastLongSelect else { return }
        lastLongSelect = nil
        guard hit.col >= 0, hit.row >= 0 else { return }
        // Stored positions are buffer-relative; UIScrollView hit points
        // are content-relative too. Do not add the scroll offset twice.
        let point = CGPoint(x: (CGFloat(hit.col) + 0.5) * cellDimension.width,
                            y: (CGFloat(hit.row) + 0.5) * cellDimension.height)
        selectWordForCopy(at: point)
    }"""

def patch_terminal_selection(checkouts, replace_once, write_source):
    ios_terminal = checkouts / "SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift"
    # Upgrade only the exact implementation produced by the previous
    # reviewed patch. Fresh pinned and repeated patched sources share the
    # same source checks below; an unexpected layout still fails closed.
    for previous, current in [
        (COPY_TOUCH_VIEW_PREVIOUS, COPY_TOUCH_VIEW),
        (COPY_HOLD_PREVIOUS, COPY_HOLD),
        (COPY_MENU_PREVIOUS, COPY_MENU),
        (COPY_STATE_PREVIOUS, COPY_STATE),
        (COPY_PAN_SETUP_PREVIOUS, COPY_PAN_SETUP),
    ]:
        if previous in ios_terminal.read_text():
            replace_once(ios_terminal, previous, current)

    replace_once(ios_terminal,
        """        // Configure the shared menu controller
        let menuController = UIMenuController.shared""",
        """        // Use the system editing menu on modern iOS. Reuse one
        // interaction rather than adding another for every long press.
        if #available(iOS 16.0, visionOS 1.0, *) {
            let interaction: UIEditMenuInteraction
            if let existing = interactions.compactMap({ $0 as? UIEditMenuInteraction }).first {
                interaction = existing
            } else {
                interaction = UIEditMenuInteraction(delegate: self)
                addInteraction(interaction)
            }
            let visible = forRegion.intersection(bounds)
            let anchor = visible.isNull ? CGPoint(x: bounds.midX, y: bounds.midY)
                : CGPoint(x: visible.midX, y: visible.minY)
            terminalEditMenuVisible = true
            interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: anchor))
            return
        }

        // Configure the shared menu controller
        let menuController = UIMenuController.shared""")
    replace_once(ios_terminal,
        "    var lastLongSelect: Position?",
        COPY_STATE)
    replace_once(ios_terminal,
        """    open override func resignFirstResponder() -> Bool {
        let code = super.resignFirstResponder()""",
        """    open override func resignFirstResponder() -> Bool {
        dismissTerminalEditMenu()
        let code = super.resignFirstResponder()""")
    replace_once(ios_terminal,
        """            if UIMenuController.shared.isMenuVisible {
                UIMenuController.shared.hideMenu()
            } else {""",
        """            if terminalEditMenuVisible || UIMenuController.shared.isMenuVisible {
                dismissTerminalEditMenu()
            } else {""")
    replace_once(ios_terminal,
        "extension TerminalViewDelegate {",
        COPY_MENU)
    for signature in ["    @objc open override func copy(_ sender: Any?) {",
                      "    @objc open override func paste (_ sender: Any?) {"]:
        replace_once(ios_terminal, signature, signature + "\n        dismissTerminalEditMenu()")
    replace_once(ios_terminal,
        """         if gestureRecognizer.state == .began {
             let _ = self.becomeFirstResponder()
             let tapLocation = gestureRecognizer.location(in: gestureRecognizer.view)
             let tapRegion = makeContextMenuRegionForTap (point: tapLocation)

             showContextMenu (forRegion: tapRegion,
                              pos: calculateTapHit (gesture: gestureRecognizer).grid)
          }
    }""".replace("\n\n", "\n" + " " * 13 + "\n"),
        COPY_HOLD)
    replace_once(ios_terminal,
        "longPress.minimumPressDuration = 0.7",
        """longPress.minimumPressDuration = 0.35
        longPress.allowableMovement = 20""")
    replace_once(ios_terminal,
        "        addGestureRecognizer(longPress)\n",
        """        addGestureRecognizer(longPress)
        copyHoldGesture = longPress
        panGestureRecognizer.require(toFail: longPress)
        panMouseGesture?.require(toFail: longPress)
""")
    replace_once(ios_terminal,
        "        panMouseGesture = gesture\n",
        """        panMouseGesture = gesture
        if let copyHoldGesture { gesture.require(toFail: copyHoldGesture) }
""")
    replace_once(ios_terminal,
        "        singleTap.require(toFail: doubleTap)",
        """        singleTap.require(toFail: longPress)
        singleTap.require(toFail: doubleTap)""")
    replace_once(ios_terminal,
        """        // A single tap belongs to an unfocused tracking application. Reserve a deliberate double
        // tap as the way to bring the software keyboard back.
        if !isFirstResponder,
           allowMouseReporting,
           withTerminal({ $0.mouseMode.sendButtonPress() }) {
            _ = becomeFirstResponder()
            return
        }

        if tapAction(tapCount: 2, gestureRecognizer: gestureRecognizer) == .selectWord {
            let hit = calculateTapHit(gesture: gestureRecognizer).grid
            withTerminal { terminal in
                selection.selectWordOrExpression(at: hit, in: terminal.displayBuffer)
                selection.selectionMode = .character
            }
            enableSelectionPanGesture()
            showContextMenu (forRegion: makeContextMenuRegionForSelection(), pos: hit)
            frameDriver.markDirty()
        }""",
        """        // Match native text selection: double-tap selects locally;
        // one tap already restores the keyboard for tracking TUIs.
        selectWordForCopy(at: gestureRecognizer.location(in: self))""")
    replace_once(ios_terminal,
        "        self.panSelectionGesture = gesture\n",
        COPY_PAN_SETUP)
    replace_once(ios_terminal,
        """            ProgramScrollRouting.capturesGesture(
                allowMouseReporting: allowMouseReporting,
                mouseTracking: (mouseMode ?? terminal.mouseMode) != .off,""",
        """            !selection.active && ProgramScrollRouting.capturesGesture(
                allowMouseReporting: allowMouseReporting,
                mouseTracking: (mouseMode ?? terminal.mouseMode) != .off,""")
    replace_once(ios_terminal,
        """            self.invalidateTerminalContents()

            if !self.withTerminal({ _ in self.selection.active }) {""",
        """            self.invalidateTerminalContents()
            self.refreshProgramScrollGesture()

            if !self.withTerminal({ _ in self.selection.active }) {
                self.dismissTerminalEditMenu()""")
    replace_once(ios_terminal,
        """        // Global reverse video needs an opaque background for its swapped text color.
        if reverseColorsActiveValue() {
            effectiveNativeBackgroundColor.setFill()
            context.fill(dirtyRect)
        }""",
        """        // Paint opaque themes into the backing store as well as the
        // layer. Clearing default cells alone can expose black pixels
        // after iOS scroll-view blits or a live appearance change.
        // Keep the original transparent path for translucent terminals.
        let backdrop = effectiveNativeBackgroundColor
        if reverseColorsActiveValue() || (backgroundOpacity >= 1 && backdrop.cgColor.alpha >= 1) {
            backdrop.setFill()
            context.fill(dirtyRect)
        }""")
    replace_once(ios_terminal,
        """            _ = forwardTap(at: gestureRecognizer.location(in: self))
            return
        }

        guard isFirstResponder else {""",
        """            _ = forwardTap(at: gestureRecognizer.location(in: self))
            // Terminal's phone UI uses one tap to open the keyboard,
            // including tmux/TUIs that enable mouse reporting. Keep the
            // remote click as well; do not consume it just for focus.
            _ = becomeFirstResponder()
            return
        }

        guard isFirstResponder else {""")

    replace_once(ios_terminal, COPY_PAN_PREVIOUS, COPY_PAN)

    service = checkouts / "SwiftTerm/Sources/SwiftTerm/SelectionService.swift"
    anchor = """    /**
     * Extends the selection by moving the end point to the new point.
     * The row is in screen coordinates
     */
    public func dragExtend (row: Int, col: Int)"""
    replace_once(service, anchor, COPY_TOUCH_SERVICE + anchor)

    replace_once(ios_terminal, COPY_STANDARD_SELECT_PREVIOUS, COPY_STANDARD_SELECT)
