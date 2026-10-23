#if canImport(AppKit)
import AppKit
import ApplicationServices

/// What is currently focused in the frontmost app, as far as AX tells us.
struct FocusInfo {
    var frame: CGRect? = nil
    var isTextInput: Bool
    var role: String?
    var descriptionText: String?
}

/// Watches the frontmost application's focused UI element via the
/// Accessibility API and reports focus changes. Drives "show keyboard when
/// editing text" and the editor-integrated-terminal detection.
final class FocusWatcher {
    var onFocusChange: ((FocusInfo) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var pollTimer: Timer?
    private var lastFocus: FocusInfo?
    private var lastTrusted: Bool?

    private static let textRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
        kAXComboBoxRole,
        "AXSearchField",
    ]

    /// Re-attaches the AX observer to the given application. Call whenever
    /// the frontmost app changes.
    func attach(to app: NSRunningApplication?) {
        detach()
        guard
            let app,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        appElement = element
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if self.lastTrusted != trusted {
                self.lastTrusted = trusted
                let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Logs")
                try? "trusted=\(trusted)\n".write(to: directory.appendingPathComponent("OpenOSK-trust-status.txt"),
                                                atomically: true, encoding: .utf8)
            }
            guard trusted else { return }
            self.evaluateCurrentFocus()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        guard AXIsProcessTrusted() else { return }

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.evaluateCurrentFocus()
        }
        guard
            AXObserverCreate(app.processIdentifier, callback, &newObserver) == .success,
            let newObserver
        else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(
            newObserver, element, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        observer = newObserver
        appElement = element
        evaluateCurrentFocus()
    }

    func detach() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastFocus = nil
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
    }

    private func evaluateCurrentFocus() {
        guard let appElement else { return }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            onFocusChange?(FocusInfo(isTextInput: false, role: nil, descriptionText: nil))
            return
        }
        reportFocus(of: value as! AXUIElement)
    }

    private func reportFocus(of element: AXUIElement) {
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        var descriptionValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element, kAXDescriptionAttribute as CFString, &descriptionValue)
        var description = descriptionValue as? String
        if description?.isEmpty != false {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            description = titleValue as? String
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        var frame: CGRect?
        if let positionValue, let sizeValue,
           CFGetTypeID(positionValue) == AXValueGetTypeID(),
           CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
               AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
               size.width > 0, size.height > 0 {
                // AX uses a top-left origin; AppKit uses the primary display's bottom-left.
                frame = CGRect(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y - size.height,
                               width: size.width, height: size.height)
            }
        }
        // Large document editors: anchor next to the insertion line, when the app exposes it.
        // Only geometry is requested; no text values or password contents are read.
        if role == kAXTextAreaRole, (frame?.height ?? 0) > 120 {
            var selection: CFTypeRef?
            var bounds: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
               let selection,
               AXUIElementCopyParameterizedAttributeValue(element,
                    kAXBoundsForRangeParameterizedAttribute as CFString, selection, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                var caret = CGRect.zero
                if AXValueGetValue(bounds as! AXValue, .cgRect, &caret),
                   caret.height > 0, caret.height < 120 {
                    frame = CGRect(x: caret.minX,
                        y: (NSScreen.screens.first?.frame.maxY ?? 0) - caret.maxY,
                        width: max(1, caret.width), height: caret.height)
                }
            }
        }
        let info = FocusInfo(
            frame: frame,
            isTextInput: role.map { Self.textRoles.contains($0) } ?? false,
            role: role,
            descriptionText: description
        )
        if let previous = lastFocus, previous.frame == info.frame,
           previous.isTextInput == info.isTextInput, previous.role == info.role,
           previous.descriptionText == info.descriptionText { return }
        lastFocus = info
        DispatchQueue.main.async { [weak self] in self?.onFocusChange?(info) }
    }
}
#endif
