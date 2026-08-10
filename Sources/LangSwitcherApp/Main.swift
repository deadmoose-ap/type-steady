import AppKit
import Darwin

@main
enum LangSwitcherMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let failureCount = SelfTestRunner.run()
            Darwin.exit(failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
