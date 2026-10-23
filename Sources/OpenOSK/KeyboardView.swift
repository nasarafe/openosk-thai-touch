#if canImport(AppKit)
import AppKit
import OpenOSKCore

/// Sizing constants for the keyboard, scaled by the user's key size setting.
struct KeyboardMetrics {
    let scale: CGFloat
    var showsCurrentText = false
    var showsSuggestionBar = false

    var unit: CGFloat { 46 * scale }
    var keyHeight: CGFloat { 46 * scale }
    var gap: CGFloat { 5 * scale }
    var padding: CGFloat { 10 * scale }
    var keyCornerRadius: CGFloat { 7 * scale }
    var panelCornerRadius: CGFloat { 14 * scale }
    var currentTextHeight: CGFloat { showsCurrentText ? 24 * scale : 0 }
    var suggestionHeight: CGFloat { showsSuggestionBar ? 34 * scale : 0 }
    var keyFontSize: CGFloat { 16 * scale }
    var secondaryFontSize: CGFloat { 9 * scale }
    var suggestionFontSize: CGFloat { 13 * scale }
    var currentTextFontSize: CGFloat { 12 * scale }

    func size(for layout: KeyboardLayout) -> NSSize {
        let maxUnits = CGFloat(layout.maxRowUnits)
        let maxKeys = CGFloat(layout.rows.map(\.count).max() ?? 0)
        let width = maxUnits * unit + max(0, maxKeys - 1) * gap + padding * 2
        let rows = CGFloat(layout.rows.count)
        let height = rows * keyHeight + (rows - 1) * gap
            + currentTextHeight + suggestionHeight + (showsSuggestionBar ? gap : 0) + padding * 2
        return NSSize(width: ceil(width), height: ceil(height))
    }
}

// MARK: - Panel backdrop

// Both backdrop views hand their clicks to the keyboard view underneath, so
// dragging the panel by its background keeps working.

private final class PassthroughEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PanelOutlineView: NSView {
    var color = NSColor.separatorColor
    var cornerRadius: CGFloat = 14

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius, yRadius: cornerRadius)
        color.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - Keyboard view

/// A native button whose fill, text and pressed state use the keyboard theme.
final class LanguageSwitchButton: NSButton {
    var theme = Theme.system
    var symbolName = "globe"
    var showsStateIndicator = false
    var isCircular = false
    var flagCode: String?
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let radius: CGFloat = isCircular ? min(rect.width, rect.height) / 2 : 7
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        (isHighlighted ? theme.pressed : theme.keyFill).setFill()
        path.fill()
        if let flagCode {
            drawFlag(flagCode)
            return
        }
        let color = isHighlighted ? theme.pressedText : theme.text
        let pointSize = font?.pointSize ?? 16
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        let textSize = title.size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: pointSize)])
        let symbolSize = symbol?.size ?? .zero
        let spacing: CGFloat = title.isEmpty || symbol == nil ? 0 : 8
        let start = (bounds.width - symbolSize.width - spacing - textSize.width) / 2
        if let symbol {
            let tinted = NSImage(size: symbolSize, flipped: false) { imageRect in
                symbol.draw(in: imageRect)
                color.set()
                imageRect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: start, y: (bounds.height - symbolSize.height) / 2,
                                  width: symbolSize.width, height: symbolSize.height))
        }
        title.draw(at: NSPoint(x: start + symbolSize.width + spacing,
                              y: (bounds.height - textSize.height) / 2),
                   withAttributes: [.font: font ?? NSFont.systemFont(ofSize: pointSize),
                                    .foregroundColor: color])
        if showsStateIndicator {
            let diameter = max(4, pointSize * 0.32)
            (state == .on ? NSColor.systemBlue : theme.secondaryText.withAlphaComponent(0.35)).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - diameter - 5,
                                      y: bounds.minY + 5, width: diameter, height: diameter)).fill()
        }
    }
    /// Vector flags remain visible when rendered offscreen in every theme.
    private func drawFlag(_ code: String) {
        let width = (font?.pointSize ?? 20) * 1.35
        let rect = NSRect(x: (bounds.width - width) / 2,
                          y: (bounds.height - width / 1.5) / 2,
                          width: width, height: width / 1.5)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).addClip()
        let red = NSColor(srgbRed: 0.75, green: 0.08, blue: 0.18, alpha: 1)
        let blue = NSColor(srgbRed: 0.12, green: 0.18, blue: 0.40, alpha: 1)
        if code == "TH" {
            for (index, color) in [red, .white, blue, blue, .white, red].enumerated() {
                color.setFill()
                NSRect(x: rect.minX, y: rect.minY + CGFloat(index) * rect.height / 6,
                       width: rect.width, height: rect.height / 6 + 0.1).fill()
            }
        } else {
            for index in 0..<13 {
                (index.isMultiple(of: 2) ? red : .white).setFill()
                NSRect(x: rect.minX, y: rect.minY + CGFloat(index) * rect.height / 13,
                       width: rect.width, height: rect.height / 13 + 0.1).fill()
            }
            let canton = NSRect(x: rect.minX, y: rect.maxY - rect.height * 7 / 13,
                                width: rect.width * 0.4, height: rect.height * 7 / 13)
            blue.setFill(); canton.fill()
            NSColor.white.setFill()
            for row in 0..<9 {
                let columns = row.isMultiple(of: 2) ? 6 : 5
                for column in 0..<columns {
                    let x = canton.minX + (CGFloat(column) + (columns == 6 ? 0.5 : 1)) * canton.width / 6
                    let y = canton.minY + (CGFloat(row) + 0.5) * canton.height / 9
                    NSBezierPath(ovalIn: NSRect(x: x - 0.2, y: y - 0.2, width: 0.4, height: 0.4)).fill()
                }
            }
        }
    }
}

final class KeyboardView: NSView {
    let layout: KeyboardLayout
    let metrics: KeyboardMetrics
    let suggestionBar = SuggestionBarView()

    var onMinimize: (() -> Void)?
    var onLanguageSwitch: (() -> Void)?
    var onFollowToggle: ((Bool) -> Void)?
    let languageButton = LanguageSwitchButton(title: "", target: nil, action: nil)
    let followButton = LanguageSwitchButton(title: "", target: nil, action: nil)
    let minimizeButton = LanguageSwitchButton(title: "", target: nil, action: nil)

    var onKeyPress: ((Key) -> Void)?
    var onKeyLongPress: ((Key, KeyView) -> Bool)?
    /// Reports pointer entering/leaving the whole keyboard (for fade logic).
    var onHoverChange: ((Bool) -> Void)?

    private var keyViews: [KeyView] = []
    private(set) var keyRows: [[KeyView]] = []
    private let currentTextLabel = NSTextField(labelWithString: "")

    /// Groups for scanning mode: the suggestion bar (if populated) followed by
    /// each key row.
    var scanGroups: [[NSView]] {
        var groups: [[NSView]] = []
        if metrics.showsSuggestionBar, !suggestionBar.scanItems.isEmpty {
            groups.append(suggestionBar.scanItems)
        }
        groups.append(contentsOf: keyRows.map { $0 })
        return groups
    }

    /// Rounded-rect mask for the blur view; stretches from its cap insets.
    private static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }

    let theme: Theme

    init(
        layout: KeyboardLayout,
        metrics: KeyboardMetrics,
        dwell: DwellConfiguration,
        theme: Theme = .system
    ) {
        self.layout = layout
        self.metrics = metrics
        self.theme = theme
        super.init(frame: NSRect(origin: .zero, size: metrics.size(for: layout)))
        wantsLayer = true
        languageButton.title = ""
        languageButton.flagCode = layout.id == "thai-kedmanee" ? "TH" : "US"
        languageButton.symbolName = ""
        languageButton.theme = theme
        languageButton.isBordered = false
        languageButton.bezelStyle = .rounded
        languageButton.font = .systemFont(ofSize: 20 * metrics.scale)
        languageButton.target = self
        languageButton.action = #selector(switchLanguage)
        languageButton.setAccessibilityLabel(L("Switch Thai / English"))
        addSubview(languageButton)
        languageButton.toolTip = L("Switch Thai / English")
        followButton.theme = theme
        followButton.symbolName = "scope"
        followButton.showsStateIndicator = true
        followButton.isBordered = false
        followButton.setButtonType(.toggle)
        followButton.font = .systemFont(ofSize: 17 * metrics.scale)
        followButton.target = self
        followButton.action = #selector(toggleFollow)
        followButton.state = (UserDefaults.standard.object(forKey: "followTextFocus") as? Bool ?? true) ? .on : .off
        followButton.setAccessibilityLabel(L("Follow text field"))
        followButton.toolTip = L(followButton.state == .on ? "Follow text field: on" : "Follow text field: off")
        addSubview(followButton)
        minimizeButton.theme = theme
        minimizeButton.symbolName = "keyboard.chevron.compact.down"
        minimizeButton.isBordered = false
        minimizeButton.font = .systemFont(ofSize: 17 * metrics.scale)
        minimizeButton.target = self
        minimizeButton.action = #selector(minimizeKeyboard)
        minimizeButton.setAccessibilityLabel(L("Minimize keyboard"))
        minimizeButton.toolTip = L("Minimize keyboard")
        addSubview(minimizeButton)

        if theme.usesVibrancy {
            let blur = PassthroughEffectView(frame: bounds)
            blur.autoresizingMask = [.width, .height]
            blur.material = .popover
            blur.blendingMode = .behindWindow
            // The panel never becomes key; without this the blur would
            // render in its washed-out inactive state.
            blur.state = .active
            blur.maskImage = Self.maskImage(cornerRadius: metrics.panelCornerRadius)
            addSubview(blur)

            // The blur covers whatever this view draws itself, outline included.
            let outline = PanelOutlineView(frame: bounds)
            outline.autoresizingMask = [.width, .height]
            outline.color = theme.border
            outline.cornerRadius = metrics.panelCornerRadius
            addSubview(outline)
        }

        if metrics.showsCurrentText {
            currentTextLabel.font = .monospacedSystemFont(
                ofSize: metrics.currentTextFontSize, weight: .regular)
            currentTextLabel.textColor = theme.panelText
            currentTextLabel.lineBreakMode = .byTruncatingHead
            currentTextLabel.alignment = .left
            addSubview(currentTextLabel)
        }

        if metrics.showsSuggestionBar {
            suggestionBar.fontSize = metrics.suggestionFontSize
            suggestionBar.spacing = metrics.gap
            suggestionBar.dwell = dwell
            suggestionBar.theme = theme
            addSubview(suggestionBar)
        }

        for row in layout.rows {
            var rowViews: [KeyView] = []
            for key in row {
                let view = KeyView(key: key)
                view.fontSize = metrics.keyFontSize
                view.secondaryFontSize = metrics.secondaryFontSize
                view.cornerRadius = metrics.keyCornerRadius
                view.dwell = dwell
                view.theme = theme
                view.onPress = { [weak self] key in self?.onKeyPress?(key) }
                view.onLongPress = { [weak self] key, keyView in
                    self?.onKeyLongPress?(key, keyView) ?? false
                }
                addSubview(view)
                keyViews.append(view)
                rowViews.append(view)
            }
            keyRows.append(rowViews)
        }
        updateKeyCaps(shifted: false, alted: false, modifierStates: [:])
        layoutKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { true }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func draw(_ dirtyRect: NSRect) {
        guard !theme.usesVibrancy else { return }
        let radius = metrics.panelCornerRadius
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        theme.background.setFill()
        path.fill()
        theme.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func setCurrentText(_ text: String) {
        guard metrics.showsCurrentText else { return }
        currentTextLabel.stringValue = text
    }

    func updateKeyCaps(
        shifted: Bool,
        alted: Bool,
        modifierStates: [Modifier: ModifierVisualState]
    ) {
        for view in keyViews {
            let key = view.key
            switch key.kind {
            case .character:
                view.displayText = key.label ?? key.output(shifted: shifted, alted: alted) ?? ""
                view.spokenLabel = view.displayText
                if !shifted, !alted, let shiftOutput = key.shift,
                   shiftOutput != key.base?.uppercased() {
                    view.secondaryText = shiftOutput
                } else {
                    view.secondaryText = nil
                }
                view.modifierState = .off
            case .special(let special):
                view.displayText = key.label ?? special.symbol
                view.spokenLabel = special.spokenName
                view.secondaryText = nil
                view.modifierState = .off
            case .modifier(let modifier):
                view.displayText = key.label ?? modifier.symbol
                view.spokenLabel = modifier.spokenName
                view.secondaryText = nil
                view.modifierState = modifierStates[modifier] ?? .off
            case .macro:
                view.displayText = key.label ?? key.text.map { String($0.prefix(6)) } ?? "◆"
                view.spokenLabel = key.label ?? key.text ?? L("Macro")
                view.secondaryText = nil
                view.modifierState = .off
            case .media(let media):
                view.displayText = key.label ?? media.symbol
                view.spokenLabel = media.spokenName
                view.secondaryText = nil
                view.modifierState = .off
            case nil:
                break
            }
            if case .media(let media) = key.kind, key.label == nil {
                // The text fallbacks are emoji, which ignore the theme.
                view.imageName = key.image ?? media.symbolName
            } else {
                view.imageName = key.image
            }
            view.needsDisplay = true
        }
    }

    @objc private func minimizeKeyboard() { onMinimize?() }
    @objc private func switchLanguage() { onLanguageSwitch?() }
    @objc private func toggleFollow() {
        followButton.toolTip = L(followButton.state == .on ? "Follow text field: on" : "Follow text field: off")
        followButton.needsDisplay = true
        onFollowToggle?(followButton.state == .on)
    }

    private func layoutKeys() {
        let m = metrics
        var y = m.padding

        if m.showsCurrentText {
            currentTextLabel.frame = NSRect(
                x: m.padding + 4,
                y: y + 2,
                width: bounds.width - (m.padding + 4) * 2,
                height: m.currentTextHeight - 4
            )
            y += m.currentTextHeight
        }

        if m.showsSuggestionBar {
            suggestionBar.frame = NSRect(
                x: m.padding,
                y: y,
                width: bounds.width - m.padding * 2,
                height: m.suggestionHeight
            )
            y += m.suggestionHeight + m.gap
        }

        var index = 0
        for (rowIndex, row) in layout.rows.enumerated() {
            let rowUnits = row.reduce(0.0) { $0 + $1.effectiveWidth }
            let rowWidth = CGFloat(rowUnits) * m.unit + CGFloat(row.count - 1) * m.gap
            var x = (bounds.width - rowWidth) / 2
            for key in row {
                let width = CGFloat(key.effectiveWidth) * m.unit
                if rowIndex == layout.rows.count - 1, key.special == .space,
                   width >= 4 * m.unit {
                    // Embed controls in the space-bar allocation without changing row width.
                    let languageWidth = m.unit
                    let followWidth = m.unit
                    let minimizeWidth = m.unit
                    let spaceWidth = width - languageWidth - followWidth - minimizeWidth - 3 * m.gap
                    languageButton.frame = NSRect(x: x, y: y, width: languageWidth, height: m.keyHeight)
                    keyViews[index].frame = NSRect(x: x + languageWidth + m.gap, y: y,
                                                  width: spaceWidth, height: m.keyHeight)
                    followButton.frame = NSRect(x: x + width - minimizeWidth - m.gap - followWidth, y: y,
                                               width: followWidth, height: m.keyHeight)
                    minimizeButton.frame = NSRect(x: x + width - minimizeWidth, y: y,
                                                 width: minimizeWidth, height: m.keyHeight)
                } else {
                    keyViews[index].frame = NSRect(x: x, y: y, width: width, height: m.keyHeight)
                }
                x += width + m.gap
                index += 1
            }
            y += m.keyHeight + m.gap
        }
    }
}
#endif
