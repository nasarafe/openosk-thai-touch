#if canImport(AppKit)
import AppKit
import AVFoundation
import OpenOSKCore

/// Coordinates the keyboard panel: key handling, modifier latching,
/// predictions, typing aids, dwell, macros and terminal mode.
final class KeyboardController: NSObject {
    enum ModifierState {
        case off
        case latched
        case locked

        var isActive: Bool { self != .off }

        var next: ModifierState {
            switch self {
            case .off: return .latched
            case .latched: return .locked
            case .locked: return .off
            }
        }

        var visual: ModifierVisualState {
            switch self {
            case .off: return .off
            case .latched: return .latched
            case .locked: return .locked
            }
        }
    }

    /// Editors whose integrated terminal is detected via the focused AX
    /// element (role + accessibility description containing "terminal").
    static let editorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",
    ]

    /// Bundle identifiers treated as terminals for command completion.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "co.zeit.hyper",
    ]

    private let injector: KeyInjector
    private let resolver: KeycodeResolver
    private let predictor = WordPredictor()
    private let shellCompleter = ShellCompleter()
    private let tracker = CompositionTracker()
    private let learnedStore = LearnedWordsStore()
    private let bigrams = BigramModel.standard()
    private let profileStore = AppProfileStore()
    private let commandUsage = CommandUsageStore()
    private let preferences = Preferences.shared
    private let variantPopup = VariantPopup()
    private let focusWatcher = FocusWatcher()
    private let scanController = ScanController()
    private let speech = AVSpeechSynthesizer()
    private(set) lazy var panels = PanelsController(keyboardController: self)

    private let panel: KeyboardPanel
    private var keyboardView: KeyboardView!
    private var layout: KeyboardLayout
    private var modifierStates: [Modifier: ModifierState] = [:]
    private var terminalMode = false
    private var didPositionPanel = false
    /// Id under which the main keyboard's position is remembered.
    private static let keyboardPanelID = "keyboard"
    private var panelWasAutoShown = false
    private var inactivityTimer: Timer?
    private var activeProfile: AppProfile?
    private var currentFocus: FocusInfo?
    private var diagnosticState = ""
    private var isCollapsed = UserDefaults.standard.bool(forKey: "keyboardCollapsed")
    private var collapsedButton: LanguageSwitchButton?
    private let collapsedSize = NSSize(width: 44, height: 44)


    init(injector: KeyInjector, resolver: KeycodeResolver) {
        self.injector = injector
        self.resolver = resolver
        self.layout = LayoutStore.layout(id: Preferences.shared.layoutID)
            ?? LayoutStore.bundledLayouts().first
            ?? KeyboardLayout(id: "empty", name: "Empty", rows: [])
        self.panel = KeyboardPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
        super.init()

        predictor.loadBundledWordlists(languages: preferences.wordlistLanguages)
        learnedStore.applyTo(predictor)
        shellCompleter.loadBundled()
        shellCompleter.loadUserCompletions()
        shellCompleter.usageCounts = commandUsage.counts
        loadSystemDictionaryIfEnabled()

        activeProfile = profileStore.profile(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        applyEffectiveLayout()
        rebuildKeyboardView()
        observeEnvironment()
        refreshTerminalMode()
        scanController.groupsProvider = { [weak self] in
            guard let self else { return [] }
            // Hidden keys must not be scanned: the user could not see them.
            let keyboard = self.isPanelVisible && !self.isCollapsed ? self.keyboardView.scanGroups : []
            return keyboard + self.panels.scanGroups
        }
        panels.onChange = { [weak self] in self?.scanController.reload() }
        applyScanningState()

        focusWatcher.onFocusChange = { [weak self] info in
            guard let self else { return }
            self.currentFocus = info
            self.handleTextFocusChange(info.isTextInput)
            self.positionNearFocusedField()
            self.refreshTerminalMode()
            self.updateSuggestions()
        }
        focusWatcher.attach(to: NSWorkspace.shared.frontmostApplication)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profilesEdited),
            name: .openOSKProfilesChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelsEdited),
            name: .openOSKPanelsChanged,
            object: nil
        )

        // Discover bare commands on $PATH for terminal completion.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let names = ShellCompleter.executableNames(
                inDirectories: ShellCompleter.defaultSearchDirectories)
            DispatchQueue.main.async {
                self?.shellCompleter.addDiscoveredCommands(names: names)
            }
        }
    }

    /// The layout that should be active considering the frontmost app's
    /// profile; returns true if the layout changed.
    @discardableResult
    private func applyEffectiveLayout() -> Bool {
        let desiredID = activeProfile?.layout ?? preferences.layoutID
        guard desiredID != layout.id, let desired = LayoutStore.layout(id: desiredID) else {
            return false
        }
        layout = desired
        return true
    }

    private func switchLanguage() {
        let next = layout.id == "thai-kedmanee" ? "qwerty-us" : "thai-kedmanee"
        guard LayoutStore.layout(id: next) != nil else { return }
        modifierStates.removeAll()
        tracker.reset()
        preferences.layoutID = next
    }

    private func positionNearFocusedField(force: Bool = false) {
        let enabled = UserDefaults.standard.object(forKey: "followTextFocus") as? Bool ?? true
        let status = "trusted=\(KeyInjector.isTrusted()) enabled=\(enabled) text=\(currentFocus?.isTextInput ?? false) frame=\(String(describing: currentFocus?.frame))"
        if status != diagnosticState {
            diagnosticState = status
            let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Logs")
            try? (status + "\n").write(to: directory.appendingPathComponent("OpenOSK-focus-status.txt"),
                                     atomically: true, encoding: .utf8)
        }
        guard UserDefaults.standard.object(forKey: "followTextFocus") as? Bool ?? true,
              panel.isVisible, currentFocus?.isTextInput == true,
              let field = currentFocus?.frame,
              (force || !panel.frame.contains(NSEvent.mouseLocation)),
              let screen = NSScreen.screens.max(by: {
                  ($0.frame.intersection(field).width * $0.frame.intersection(field).height)
                      < ($1.frame.intersection(field).width * $1.frame.intersection(field).height)
              }), screen.frame.intersects(field)
        else { return }
        let origin = KeyboardPlacement.origin(near: field, keyboardSize: panel.frame.size,
                                               visibleFrame: screen.visibleFrame)
        if abs(panel.frame.minX - origin.x) > 2 || abs(panel.frame.minY - origin.y) > 2 {
            panel.setFrameOrigin(origin)
        }
    }

    private func applyScanningState() {
        if preferences.scanningEnabled && !isCollapsed {
            scanController.interval = preferences.scanInterval
            let advanceKey = preferences.scanAdvanceKey
            scanController.start(
                switchKey: preferences.scanSwitchKey,
                advanceKey: advanceKey == "none" ? nil : advanceKey
            )
        } else {
            scanController.stop()
        }
    }

    private var systemDictionaryLoaded = false

    private func loadSystemDictionaryIfEnabled() {
        if preferences.systemDictionaryEnabled {
            guard !systemDictionaryLoaded else { return }
            systemDictionaryLoaded = true
            let predictor = self.predictor
            DispatchQueue.global(qos: .utility).async {
                predictor.loadFallbackDictionary(atPath: "/usr/share/dict/words")
            }
        } else if systemDictionaryLoaded {
            systemDictionaryLoaded = false
            predictor.clearFallbackDictionary()
        }
    }

    // MARK: - Panel

    var isPanelVisible: Bool { panel.isVisible }

    func showPanel(automatically: Bool = false) {
        if !didPositionPanel {
            if !panel.restoreOrigin(forID: Self.keyboardPanelID) {
                positionAtBottomCenter()
            }
            panel.trackOrigin(as: Self.keyboardPanelID)
            didPositionPanel = true
        }
        panelWasAutoShown = automatically
        panel.orderFrontRegardless()
        noteActivity()
        scanController.reload()
    }

    @objc private func collapseKeyboard() {
        variantPopup.dismiss()
        isCollapsed = true
        UserDefaults.standard.set(true, forKey: "keyboardCollapsed")
        panelWasAutoShown = false
        applyPresentation()
        applyScanningState()
        positionNearFocusedField(force: true)
        noteActivity()
    }

    @objc private func expandKeyboard() {
        isCollapsed = false
        UserDefaults.standard.set(false, forKey: "keyboardCollapsed")
        applyPresentation()
        applyScanningState()
        positionNearFocusedField(force: true)
        // If there is no editable field, keep the expanded keyboard on its current screen.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) {
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            panel.setFrameOrigin(NSPoint(
                x: min(max(panel.frame.minX, visible.minX), max(visible.minX, visible.maxX - panel.frame.width)),
                y: min(max(panel.frame.minY, visible.minY), max(visible.minY, visible.maxY - panel.frame.height))))
        }
        noteActivity()
    }

    private func applyPresentation() {
        let origin = panel.frame.origin
        if isCollapsed {
            let container = NSView(frame: NSRect(origin: .zero, size: collapsedSize))
            let button = LanguageSwitchButton(title: "", target: self, action: #selector(expandKeyboard))
            button.frame = container.bounds
            button.isBordered = false
            button.isCircular = true
            button.symbolName = "keyboard"
            button.font = .systemFont(ofSize: 20)
            button.theme = Theme.theme(id: preferences.themeID)
            button.showsStateIndicator = true
            button.state = (UserDefaults.standard.object(forKey: "followTextFocus") as? Bool ?? true) ? .on : .off
            button.setAccessibilityLabel(L("Expand keyboard"))
            button.toolTip = L("Expand keyboard")
            container.addSubview(button)
            collapsedButton = button
            panel.setContentSize(collapsedSize)
            panel.contentView = container
        } else {
            collapsedButton = nil
            panel.setContentSize(keyboardView.metrics.size(for: layout))
            panel.contentView = keyboardView
        }
        panel.setFrameOrigin(origin)
    }

    func hidePanel() {
        variantPopup.dismiss()
        panelWasAutoShown = false
        panel.orderOut(nil)
        scanController.reload()
    }

    func togglePanel() {
        isPanelVisible ? hidePanel() : showPanel()
    }

    /// Local diagnostic: exercise the real language button and render both layouts.
    func checkLanguageButtonAndRender(to directory: URL) throws {
        let original = preferences.layoutID
        let originallyCollapsed = isCollapsed
        let originalFocus = currentFocus
        let originalOrigin = panel.frame.origin
        let originalFollowMode = UserDefaults.standard.object(forKey: "followTextFocus")
        if isCollapsed { expandKeyboard() }
        defer {
            currentFocus = originalFocus
            preferences.layoutID = original
            if originallyCollapsed { collapseKeyboard() }
            panel.setFrameOrigin(originalOrigin)
            if let originalFollowMode {
                UserDefaults.standard.set(originalFollowMode, forKey: "followTextFocus")
            } else {
                UserDefaults.standard.removeObject(forKey: "followTextFocus")
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for _ in 0..<2 {
            let controls = [keyboardView.languageButton.frame, keyboardView.followButton.frame, keyboardView.minimizeButton.frame]
            let bottomKeys = keyboardView.keyRows.last ?? []
            guard let firstKey = keyboardView.keyRows.first?.first,
                  firstKey.frame.minY == keyboardView.metrics.padding,
                  controls.allSatisfy({ keyboardView.bounds.contains($0) }),
                  !controls[0].intersects(controls[1]), !controls[0].intersects(controls[2]),
                  !controls[1].intersects(controls[2]),
                  bottomKeys.allSatisfy({ key in controls.allSatisfy { !key.frame.intersects($0) } })
            else { throw NSError(domain: "OpenOSKCompactLayout", code: 4) }
            let originalFollow = keyboardView.followButton.state
            keyboardView.followButton.performClick(nil)
            guard keyboardView.followButton.state != originalFollow,
                  UserDefaults.standard.bool(forKey: "followTextFocus") == (keyboardView.followButton.state == .on)
            else { throw NSError(domain: "OpenOSKFollowToggle", code: 5) }
            keyboardView.followButton.performClick(nil)
            guard keyboardView.followButton.state == originalFollow
            else { throw NSError(domain: "OpenOSKFollowToggle", code: 6) }
            guard let bitmap = keyboardView.bitmapImageRepForCachingDisplay(in: keyboardView.bounds)
            else { throw NSError(domain: "OpenOSKPreview", code: 1) }
            keyboardView.cacheDisplay(in: keyboardView.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:])
            else { throw NSError(domain: "OpenOSKPreview", code: 2) }
            try data.write(to: directory.appendingPathComponent(layout.id + ".png"))
            let expected = layout.id == "thai-kedmanee" ? "qwerty-us" : "thai-kedmanee"
            keyboardView.languageButton.performClick(nil)
            guard layout.id == expected, preferences.layoutID == expected
            else { throw NSError(domain: "OpenOSKLanguageSwitch", code: 3) }
        }
        if let screen = NSScreen.main {
            UserDefaults.standard.set(true, forKey: "followTextFocus")
            let field = CGRect(x: screen.visibleFrame.midX - 100,
                               y: screen.visibleFrame.midY, width: 200, height: 30)
            currentFocus = FocusInfo(frame: field, isTextInput: true, role: "AXTextField", descriptionText: nil)
            let fullSize = panel.frame.size
            let savedLayout = layout.id
            keyboardView.minimizeButton.performClick(nil)
            guard isCollapsed, panel.frame.size == collapsedSize, let collapsedButton
            else { throw NSError(domain: "OpenOSKCollapse", code: 7) }
            let firstOrigin = panel.frame.origin
            let nextField = field.offsetBy(dx: 200, dy: 100)
            currentFocus = FocusInfo(frame: nextField, isTextInput: true, role: "AXTextField", descriptionText: nil)
            positionNearFocusedField(force: true)
            guard panel.frame.origin != firstOrigin,
                  !panel.frame.intersects(nextField)
            else { throw NSError(domain: "OpenOSKCollapsedFollow", code: 8) }
            if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("collapsed.png"))
            }
            collapsedButton.performClick(nil)
            guard !isCollapsed, panel.frame.size == fullSize, layout.id == savedLayout,
                  panel.contentView === keyboardView
            else { throw NSError(domain: "OpenOSKExpand", code: 9) }
        }
        print("MINIMIZE_FOLLOW_RESTORE_OK: real minimize/expand buttons, 44pt target follows field, layout preserved")
        print("COMPACT_LAYOUT_OK: no header, controls within bottom row, follow toggle works")
        print("LANGUAGE_BUTTON_OK: Thai → English → Thai (or reverse)")
    }

    func clearLearnedWords() {
        learnedStore.clear()
        predictor.clearLearned()
        bigrams.clear()
        updateSuggestions()
    }

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.minY + 12
        ))
    }

    private func rebuildKeyboardView() {
        var metrics = KeyboardMetrics(scale: CGFloat(preferences.scale))
        metrics.showsCurrentText = false
        metrics.showsSuggestionBar = false
        let dwell = DwellConfiguration(
            enabled: preferences.dwellEnabled,
            time: preferences.dwellTime
        )

        let view = KeyboardView(
            layout: layout,
            metrics: metrics,
            dwell: dwell,
            theme: Theme.theme(id: preferences.themeID)
        )
        view.onMinimize = { [weak self] in self?.collapseKeyboard() }
        view.onLanguageSwitch = { [weak self] in self?.switchLanguage() }
        view.onFollowToggle = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: "followTextFocus")
            if enabled { self?.positionNearFocusedField() }
        }
        view.onKeyPress = { [weak self] key in self?.handleKey(key) }
        view.onKeyLongPress = { [weak self] key, keyView in
            self?.handleLongPress(key, keyView: keyView) ?? false
        }
        view.onHoverChange = { [weak self] hovering in
            if hovering { self?.noteActivity() }
        }
        view.suggestionBar.onSelect = { [weak self] suggestion in
            self?.acceptSuggestion(suggestion)
        }
        keyboardView = view

        applyPresentation()
        panel.alphaValue = CGFloat(preferences.opacity)
        refreshKeyCaps()
        updateSuggestions()
        noteActivity()
        scanController.reload()
    }

    // MARK: - Inactivity fade

    /// Restores full opacity and restarts the inactivity countdown.
    private func noteActivity() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = CGFloat(preferences.opacity)
        }
        inactivityTimer?.invalidate()
        guard !isCollapsed else { return }
        guard preferences.inactivityFadeEnabled, preferences.inactivityFadeDelay > 0 else {
            return
        }
        let timer = Timer(
            timeInterval: preferences.inactivityFadeDelay, repeats: false
        ) { [weak self] _ in
            self?.fadeOut()
        }
        RunLoop.main.add(timer, forMode: .common)
        inactivityTimer = timer
    }

    private func fadeOut() {
        guard panel.isVisible, !isCollapsed else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            panel.animator().alphaValue = max(0.12, CGFloat(preferences.opacity) * 0.2)
        }
    }

    // MARK: - Environment observation

    private func observeEnvironment() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: Preferences.didChangeNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func frontmostAppChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        let isSelf = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier

        if !isSelf {
            activeProfile = profileStore.profile(for: app?.bundleIdentifier)
            if applyEffectiveLayout() {
                rebuildKeyboardView()
            }
        }
        refreshTerminalMode()
        tracker.reset()
        updateSuggestions()

        if !isSelf {
            focusWatcher.attach(to: app)
        }
    }

    /// Reacts to the one preference that changed; rebuilding the views for
    /// every change made sliders stutter and dropped hover and scan state.
    @objc private func preferencesChanged(_ notification: Notification) {
        guard let key = Preferences.changedKey(in: notification) else { return }
        switch key {
        case .layoutID:
            if applyEffectiveLayout() {
                rebuildKeyboardView()
            }
        case .scale, .themeID, .dwellEnabled, .dwellTime:
            rebuildKeyboardView()
            panels.rebuildOpenPanels()
        case .showCurrentText:
            rebuildKeyboardView()
        case .opacity:
            panels.setOpacity(CGFloat(preferences.opacity))
            // Fades the keyboard itself to the new opacity.
            noteActivity()
        case .inactivityFadeEnabled, .inactivityFadeDelay:
            noteActivity()
        case .scanningEnabled, .scanInterval, .scanSwitchKey, .scanAdvanceKey:
            applyScanningState()
        case .systemDictionaryEnabled:
            loadSystemDictionaryIfEnabled()
        case .predictionsEnabled, .terminalCompletionsEnabled:
            updateSuggestions()
        case .learningEnabled, .texterPasteMode, .wordlistLanguages, .autoCapitalization,
             .autoSpacing, .autoShowOnTextFocus, .openPanelIDs, .keyClickSound, .panelOrigins,
             .followTextFocus, .keyboardCollapsed:
            // Read at the point of use.
            break
        }
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.resolver.rebuild()
        }
    }

    private func refreshTerminalMode() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let forced = activeProfile?.terminalMode {
            terminalMode = forced
        } else if let bundleID, Self.editorBundleIDs.contains(bundleID) {
            // Inside supported editors, follow the focused element: the
            // integrated terminal is a text area labeled "Terminal …".
            let description = currentFocus?.descriptionText?.lowercased() ?? ""
            terminalMode = currentFocus?.role == "AXTextArea"
                && description.contains("terminal")
        } else {
            terminalMode = bundleID.map { Self.terminalBundleIDs.contains($0) } ?? false
        }
    }

    @objc private func profilesEdited(_ notification: Notification) {
        profileStore.reload()
        activeProfile = profileStore.profile(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        if applyEffectiveLayout() {
            rebuildKeyboardView()
        }
        refreshTerminalMode()
        updateSuggestions()
    }

    @objc private func panelsEdited(_ notification: Notification) {
        panels.rebuildOpenPanels()
    }

    private func handleTextFocusChange(_ hasTextFocus: Bool) {
        if isCollapsed {
            if hasTextFocus && !isPanelVisible { showPanel() }
            return
        }
        guard preferences.autoShowOnTextFocus else { return }
        if hasTextFocus {
            if !isPanelVisible {
                showPanel(automatically: true)
            }
        } else if panelWasAutoShown {
            hidePanel()
        }
    }

    // MARK: - Modifier handling

    private func isActive(_ modifier: Modifier) -> Bool {
        (modifierStates[modifier] ?? .off).isActive
    }

    private func currentFlags() -> CGEventFlags {
        var flags: CGEventFlags = []
        for (modifier, state) in modifierStates where state.isActive {
            flags.insert(modifier.flags)
        }
        return flags
    }

    private func releaseLatchedModifiers() {
        for (modifier, state) in modifierStates where state == .latched {
            modifierStates[modifier] = .off
        }
    }

    private func refreshKeyCaps() {
        keyboardView.updateKeyCaps(
            shifted: isActive(.shift),
            alted: isActive(.option),
            modifierStates: modifierStates.mapValues(\.visual)
        )
    }

    // MARK: - Key handling

    func handleKey(_ key: Key) {
        guard let kind = key.kind else { return }
        variantPopup.dismiss()
        noteActivity()
        if preferences.keyClickSound {
            NSSound(named: "Tink")?.play()
        }

        switch kind {
        case .modifier(let modifier):
            modifierStates[modifier] = (modifierStates[modifier] ?? .off).next
            refreshKeyCaps()
            return

        case .character:
            handleCharacterKey(key)

        case .special(let special):
            handleSpecialKey(special)

        case .macro(let macro):
            runMacro(macro)

        case .media(let media):
            MediaKeyInjector.press(media)
        }
        releaseLatchedModifiers()
        refreshKeyCaps()
        updateSuggestions()
    }

    /// Long-press on a character key: show the variant popup. Returns whether
    /// the popup was shown (which suppresses the normal key press).
    private func handleLongPress(_ key: Key, keyView: KeyView) -> Bool {
        guard let base = key.base else { return false }
        let variants = CharacterVariants.variants(for: base, shifted: isActive(.shift))
        guard !variants.isEmpty else { return false }

        variantPopup.show(
            variants: variants,
            relativeTo: keyView,
            metrics: keyboardView.metrics,
            theme: keyboardView.theme
        ) { [weak self] variant in
            guard let self else { return }
            self.injector.typeText(variant)
            self.tracker.typed(variant)
            self.releaseLatchedModifiers()
            self.refreshKeyCaps()
            self.updateSuggestions()
        }
        return true
    }

    private func handleCharacterKey(_ key: Key) {
        let shifted = isActive(.shift)
        let alted = isActive(.option)

        if isActive(.command) || isActive(.control) {
            // Keyboard shortcut: post the real key code for the base character.
            guard let character = key.base?.first,
                  let resolution = resolver.resolve(character)
            else { return }
            var flags = currentFlags()
            if resolution.needsShift { flags.insert(.maskShift) }
            injector.pressKey(resolution.keyCode, flags: flags)
            tracker.reset()
            return
        }

        guard var output = key.output(shifted: shifted, alted: alted) else { return }

        if preferences.autoCapitalization, !terminalMode, !shifted, !alted,
           output.count == 1, output.first!.isLowercase,
           TypingAids.shouldAutoCapitalize(afterLine: tracker.line) {
            output = output.uppercased()
        }

        injector.typeText(output)
        tracker.typed(output)
    }

    private func handleSpecialKey(_ special: SpecialKey) {
        let flags = currentFlags()
        switch special {
        case .space:
            if preferences.autoSpacing, !terminalMode, flags.isEmpty,
               TypingAids.shouldInsertPeriodOnDoubleSpace(line: tracker.line) {
                // Second space of a double-space becomes ". ".
                injector.pressKey(SpecialKey.delete.keyCode)
                injector.typeText(". ")
                tracker.backspaced()
                tracker.typed(". ")
                return
            }
            commitCurrentWord()
            injector.pressKey(special.keyCode, flags: flags)
            tracker.typed(" ")
        case .return:
            commitCurrentWord()
            injector.pressKey(special.keyCode, flags: flags)
            let line = tracker.submittedLine()
            if terminalMode {
                recordCommandUsage(fromLine: line)
            }
        case .delete:
            injector.pressKey(special.keyCode, flags: flags)
            tracker.backspaced()
        case .forwardDelete, .tab, .escape,
             .left, .right, .up, .down, .home, .end, .pageUp, .pageDown:
            // These move the caret or hand control to the target application,
            // so our model of the current line is no longer reliable.
            injector.pressKey(special.keyCode, flags: flags)
            tracker.reset()
        }
    }

    private func commitCurrentWord() {
        guard !terminalMode, preferences.learningEnabled else { return }
        let word = tracker.currentWord
        guard word.count >= 3 else { return }
        predictor.learn(word)
        learnedStore.record(word)
        let previous = tracker.previousWord
        if !previous.isEmpty {
            bigrams.learn(previous: previous, next: word)
        }
    }

    private func recordCommandUsage(fromLine line: String) {
        var tokens = line.split(separator: " ").map(String.init)
        while let first = tokens.first,
              ["sudo", "env", "time", "nohup"].contains(first) {
            tokens.removeFirst()
        }
        guard let command = tokens.first, !command.isEmpty else { return }
        commandUsage.record(command: command)
        shellCompleter.usageCounts = commandUsage.counts
    }

    // MARK: - Macros

    private func runMacro(_ macro: Macro) {
        if macro.isPlainText {
            for step in macro.steps {
                if let text = step.text { tracker.typed(text) }
            }
        } else {
            tracker.reset()
        }

        let injector = self.injector
        let resolver = self.resolver
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for step in macro.steps {
                if let delay = step.delayMs, delay > 0 {
                    usleep(useconds_t(delay) * 1000)
                }
                if let text = step.text {
                    injector.typeText(text)
                }
                if let shortcut = step.shortcut,
                   let parsed = ShortcutParser.parse(shortcut) {
                    if let special = parsed.special {
                        injector.pressKey(special.keyCode, flags: parsed.flags)
                    } else if let character = parsed.character,
                              let resolution = resolver.resolve(character) {
                        var flags = parsed.flags
                        if resolution.needsShift { flags.insert(.maskShift) }
                        injector.pressKey(resolution.keyCode, flags: flags)
                    }
                }
                if let target = step.open {
                    DispatchQueue.main.async { Self.open(target) }
                }
                if let panelID = step.panel {
                    DispatchQueue.main.async {
                        self?.panels.toggle(panelID: panelID)
                    }
                }
                if let phrase = step.say {
                    DispatchQueue.main.async {
                        self?.speech.speak(AVSpeechUtterance(string: phrase))
                    }
                }
            }
        }
    }

    private static func open(_ target: String) {
        if target.hasPrefix("/") || target.hasPrefix("~") {
            let path = (target as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Suggestions & current text

    private func updateSuggestions() {
        keyboardView.suggestionBar.setSuggestions(computeSuggestions())
        keyboardView.setCurrentText(tracker.line)
    }

    private func computeSuggestions() -> [String] {
        guard preferences.predictionsEnabled else { return [] }
        if terminalMode {
            guard preferences.terminalCompletionsEnabled, !tracker.line.isEmpty else { return [] }
            return shellCompleter.suggestions(forLine: tracker.line)
        }
        let word = tracker.currentWord
        if word.isEmpty {
            // Next-word prediction from learned bigrams after a completed word.
            let last = tracker.lastCompletedWord
            guard !last.isEmpty, tracker.line.hasSuffix(" ") else { return [] }
            return bigrams.suggestions(after: last)
        }
        return predictor.suggestions(forPrefix: word)
    }

    private func acceptSuggestion(_ suggestion: String) {
        noteActivity()
        let bigramContext = terminalMode ? "" : tracker.previousWord
        let prefix = terminalMode ? tracker.currentToken : tracker.currentWord
        let completion: String
        if suggestion.lowercased().hasPrefix(prefix.lowercased()) {
            completion = String(suggestion.dropFirst(prefix.count)) + " "
        } else {
            completion = suggestion + " "
        }
        injector.typeText(completion)
        tracker.typed(completion)

        if !terminalMode, preferences.learningEnabled, suggestion.count >= 3 {
            predictor.learn(suggestion)
            learnedStore.record(suggestion)
            if !bigramContext.isEmpty {
                bigrams.learn(previous: bigramContext, next: suggestion)
            }
        }
        updateSuggestions()
    }
}
#endif
