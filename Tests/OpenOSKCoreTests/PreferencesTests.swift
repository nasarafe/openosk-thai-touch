import Foundation
import Testing

@testable import OpenOSKCore

@Suite struct PreferencesTests {
    private func makePreferences() -> Preferences {
        let suite = "OpenOSKTests-\(UUID().uuidString)"
        return Preferences(defaults: UserDefaults(suiteName: suite)!)
    }

    /// Collects the keys `preferences` announces. The sender is matched here
    /// rather than through the observer's `object:` filter, which on Linux
    /// never matches a sender that is not an `NSObject`; other suites post
    /// the same notification from their own instances in parallel.
    private final class ChangeLog: @unchecked Sendable {
        private(set) var keys: [Preferences.Key] = []
        private var observer: NSObjectProtocol?

        init(of preferences: Preferences) {
            observer = NotificationCenter.default.addObserver(
                forName: Preferences.didChangeNotification, object: nil, queue: nil
            ) { [weak self, weak preferences] notification in
                guard (notification.object as AnyObject?) === preferences,
                      let key = Preferences.changedKey(in: notification)
                else { return }
                self?.keys.append(key)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    @Test func changeNotificationNamesTheChangedKey() {
        let preferences = makePreferences()
        let log = ChangeLog(of: preferences)

        preferences.opacity = 0.5
        preferences.themeID = "light"

        #expect(log.keys == [.opacity, .themeID])
    }

    @Test func unchangedValuesDoNotNotify() {
        let preferences = makePreferences()
        preferences.scale = 1.2
        let log = ChangeLog(of: preferences)

        preferences.scale = 1.2
        #expect(log.keys.isEmpty)

        // Guards against passing only because nothing is ever logged.
        preferences.scale = 1.3
        #expect(log.keys == [.scale])
    }

    @Test func panelOriginRoundTrips() {
        let preferences = makePreferences()
        #expect(preferences.panelOrigin(forID: "keyboard") == nil)

        preferences.setPanelOrigin(x: 12.5, y: 80, forID: "keyboard")

        let origin = preferences.panelOrigin(forID: "keyboard")
        #expect(origin?.x == 12.5)
        #expect(origin?.y == 80)
    }
}
