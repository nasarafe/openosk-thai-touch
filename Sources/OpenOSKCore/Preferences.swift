import Foundation

/// User preferences, backed by `UserDefaults`.
public final class Preferences {
    public static let shared = Preferences()
    public static let didChangeNotification = Notification.Name("OpenOSKPreferencesDidChange")

    private let defaults: UserDefaults

    public static let defaultSettings: [String: Any] = [
        Key.layoutID.rawValue: "thai-kedmanee",
        Key.scale.rawValue: 0.9194826013901654,
        Key.opacity.rawValue: 0.9063957509273239,
        Key.predictionsEnabled.rawValue: true,
        Key.learningEnabled.rawValue: true,
        Key.terminalCompletionsEnabled.rawValue: true,
        Key.texterPasteMode.rawValue: true,
        Key.wordlistLanguages.rawValue: ["de", "en"],
        Key.autoCapitalization.rawValue: true,
        Key.autoSpacing.rawValue: true,
        Key.showCurrentText.rawValue: false,
        Key.dwellEnabled.rawValue: false,
        Key.dwellTime.rawValue: 0.9,
        Key.inactivityFadeEnabled.rawValue: true,
        Key.inactivityFadeDelay.rawValue: 10.0,
        Key.autoShowOnTextFocus.rawValue: true,
        Key.scanningEnabled.rawValue: false,
        Key.scanInterval.rawValue: 1.2,
        Key.scanSwitchKey.rawValue: "space",
        Key.openPanelIDs.rawValue: [String](),
        Key.themeID.rawValue: "dark",
        Key.keyClickSound.rawValue: true,
        Key.systemDictionaryEnabled.rawValue: false,
        Key.scanAdvanceKey.rawValue: "none",
        Key.followTextFocus.rawValue: true,
        Key.keyboardCollapsed.rawValue: false,
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.defaultSettings)
    }

    /// Every stored preference; the raw value is the `UserDefaults` key.
    public enum Key: String, CaseIterable {
        case layoutID
        case scale = "keyboardScale"
        case opacity = "keyboardOpacity"
        case predictionsEnabled
        case learningEnabled
        case terminalCompletionsEnabled
        case texterPasteMode
        case wordlistLanguages
        case autoCapitalization
        case autoSpacing
        case showCurrentText
        case dwellEnabled
        case dwellTime
        case inactivityFadeEnabled
        case inactivityFadeDelay
        case autoShowOnTextFocus
        case scanningEnabled
        case scanInterval
        case scanSwitchKey
        case openPanelIDs
        case themeID
        case keyClickSound
        case systemDictionaryEnabled
        case scanAdvanceKey
        case followTextFocus
        case keyboardCollapsed
        case panelOrigins
    }

    public var layoutID: String {
        get { defaults.string(forKey: Key.layoutID.rawValue) ?? "thai-kedmanee" }
        set { set(newValue, forKey: .layoutID) }
    }

    /// Key size multiplier (1.0 = standard).
    public var scale: Double {
        get { defaults.double(forKey: Key.scale.rawValue) }
        set { set(newValue, forKey: .scale) }
    }

    public var opacity: Double {
        get { defaults.double(forKey: Key.opacity.rawValue) }
        set { set(newValue, forKey: .opacity) }
    }

    public var predictionsEnabled: Bool {
        get { defaults.bool(forKey: Key.predictionsEnabled.rawValue) }
        set { set(newValue, forKey: .predictionsEnabled) }
    }

    public var learningEnabled: Bool {
        get { defaults.bool(forKey: Key.learningEnabled.rawValue) }
        set { set(newValue, forKey: .learningEnabled) }
    }

    public var terminalCompletionsEnabled: Bool {
        get { defaults.bool(forKey: Key.terminalCompletionsEnabled.rawValue) }
        set { set(newValue, forKey: .terminalCompletionsEnabled) }
    }

    /// Whether the Texter inserts via clipboard + ⌘V instead of typing.
    public var texterPasteMode: Bool {
        get { defaults.bool(forKey: Key.texterPasteMode.rawValue) }
        set { set(newValue, forKey: .texterPasteMode) }
    }

    public var wordlistLanguages: [String] {
        get { defaults.stringArray(forKey: Key.wordlistLanguages.rawValue) ?? ["de", "en"] }
        set { set(newValue, forKey: .wordlistLanguages) }
    }

    /// Capitalize the first letter after sentence-ending punctuation.
    public var autoCapitalization: Bool {
        get { defaults.bool(forKey: Key.autoCapitalization.rawValue) }
        set { set(newValue, forKey: .autoCapitalization) }
    }

    /// Double-space inserts ". ".
    public var autoSpacing: Bool {
        get { defaults.bool(forKey: Key.autoSpacing.rawValue) }
        set { set(newValue, forKey: .autoSpacing) }
    }

    /// Show the current-text bar on the keyboard.
    public var showCurrentText: Bool {
        get { defaults.bool(forKey: Key.showCurrentText.rawValue) }
        set { set(newValue, forKey: .showCurrentText) }
    }

    /// Hovering a key presses it after `dwellTime`.
    public var dwellEnabled: Bool {
        get { defaults.bool(forKey: Key.dwellEnabled.rawValue) }
        set { set(newValue, forKey: .dwellEnabled) }
    }

    /// Dwell duration in seconds.
    public var dwellTime: Double {
        get { defaults.double(forKey: Key.dwellTime.rawValue) }
        set { set(newValue, forKey: .dwellTime) }
    }

    /// Fade the keyboard after a period without interaction.
    public var inactivityFadeEnabled: Bool {
        get { defaults.bool(forKey: Key.inactivityFadeEnabled.rawValue) }
        set { set(newValue, forKey: .inactivityFadeEnabled) }
    }

    /// Seconds of inactivity before the keyboard fades.
    public var inactivityFadeDelay: Double {
        get { defaults.double(forKey: Key.inactivityFadeDelay.rawValue) }
        set { set(newValue, forKey: .inactivityFadeDelay) }
    }

    /// Show the keyboard automatically when a text field gains focus.
    public var autoShowOnTextFocus: Bool {
        get { defaults.bool(forKey: Key.autoShowOnTextFocus.rawValue) }
        set { set(newValue, forKey: .autoShowOnTextFocus) }
    }

    /// Scanning (switch access) input mode.
    public var scanningEnabled: Bool {
        get { defaults.bool(forKey: Key.scanningEnabled.rawValue) }
        set { set(newValue, forKey: .scanningEnabled) }
    }

    /// Seconds between scan highlight steps.
    public var scanInterval: Double {
        get { defaults.double(forKey: Key.scanInterval.rawValue) }
        set { set(newValue, forKey: .scanInterval) }
    }

    /// Hardware key acting as the scan switch: "space", "return", "f13"–"f15".
    public var scanSwitchKey: String {
        get { defaults.string(forKey: Key.scanSwitchKey.rawValue) ?? "space" }
        set { set(newValue, forKey: .scanSwitchKey) }
    }

    /// Custom panels that are currently open (restored on launch).
    public var openPanelIDs: [String] {
        get { defaults.stringArray(forKey: Key.openPanelIDs.rawValue) ?? [] }
        set { set(newValue, forKey: .openPanelIDs) }
    }

    /// Visual theme id ("system", "high-contrast", "dark", "light").
    public var themeID: String {
        get { defaults.string(forKey: Key.themeID.rawValue) ?? "dark" }
        set { set(newValue, forKey: .themeID) }
    }

    /// Play a click sound on key press.
    public var keyClickSound: Bool {
        get { defaults.bool(forKey: Key.keyClickSound.rawValue) }
        set { set(newValue, forKey: .keyClickSound) }
    }

    /// Merge /usr/share/dict/words as low-priority prediction fallback.
    public var systemDictionaryEnabled: Bool {
        get { defaults.bool(forKey: Key.systemDictionaryEnabled.rawValue) }
        set { set(newValue, forKey: .systemDictionaryEnabled) }
    }

    /// Optional second switch that advances the scan manually ("none"
    /// disables it; otherwise same key names as `scanSwitchKey`). With an
    /// advance key set, the automatic scan timer is disabled.
    public var scanAdvanceKey: String {
        get { defaults.string(forKey: Key.scanAdvanceKey.rawValue) ?? "none" }
        set { set(newValue, forKey: .scanAdvanceKey) }
    }

    // MARK: - Panel positions

    /// Last position of a floating panel, keyed by panel id ("keyboard" for
    /// the main keyboard). Nil until the user has moved that panel.
    public func panelOrigin(forID id: String) -> (x: Double, y: Double)? {
        // Up to v0.5 only the keyboard's position was stored, under its own key.
        let legacy = id == "keyboard" ? defaults.array(forKey: "panelOrigin") as? [Double] : nil
        guard let stored = panelOrigins[id] ?? legacy, stored.count == 2 else { return nil }
        return (stored[0], stored[1])
    }

    public func setPanelOrigin(x: Double, y: Double, forID id: String) {
        var origins = panelOrigins
        origins[id] = [x, y]
        set(origins, forKey: .panelOrigins)
    }

    private var panelOrigins: [String: [Double]] {
        defaults.dictionary(forKey: Key.panelOrigins.rawValue) as? [String: [Double]] ?? [:]
    }

    // MARK: - Change notification

    /// The preference a `didChangeNotification` was posted for.
    public static func changedKey(in notification: Notification) -> Key? {
        notification.userInfo?[changedKeyUserInfoKey] as? Key
    }

    private static let changedKeyUserInfoKey = "key"

    private func set<Value: Equatable>(_ value: Value, forKey key: Key) {
        // Sliders report every intermediate position and menus re-select the
        // current item; observers rebuild UI, so only real changes are posted.
        if defaults.object(forKey: key.rawValue) as? Value == value { return }
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.changedKeyUserInfoKey: key]
        )
    }
}
