#if canImport(AppKit)
import AppKit
import OpenOSKCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var keyboardController: KeyboardController!
    private(set) var texterController: TexterController!
    private(set) var settingsController: SettingsController!
    private(set) var profileEditorController = ProfileEditorController()
    private(set) var panelEditorController = PanelEditorController()
    private var statusBarController: StatusBarController!

    private let injector = KeyInjector()
    private let resolver = KeycodeResolver()

    private var isSmokeTest: Bool {
        CommandLine.arguments.contains("--smoke-test")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardController = KeyboardController(injector: injector, resolver: resolver)
        texterController = TexterController(injector: injector, resolver: resolver)
        settingsController = SettingsController(
            onClearLearnedWords: { [weak self] in self?.keyboardController.clearLearnedWords() })
        statusBarController = StatusBarController(appDelegate: self)

        keyboardController.showPanel()
        keyboardController.panels.restoreOpenPanels()

        if let index = CommandLine.arguments.firstIndex(of: "--local-ui-check"),
           CommandLine.arguments.indices.contains(index + 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                do {
                    try self.keyboardController.checkLanguageButtonAndRender(
                        to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    print("LOCAL_UI_CHECK_OK")
                    NSApp.terminate(nil)
                } catch {
                    fputs("UI check failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }

        if isSmokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                print("SMOKE_TEST_OK")
                NSApp.terminate(nil)
            }
            return
        }

        if !KeyInjector.isTrusted(promptIfNeeded: true) {
            // The system shows its own prompt; nothing else to do here.
            NSLog("OpenOSK is waiting for Accessibility access to be granted.")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
#endif
