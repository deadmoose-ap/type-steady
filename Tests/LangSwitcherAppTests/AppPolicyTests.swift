import Testing
@testable import LangSwitcherApp

struct AppPolicyTests {
    @Test func protectsStructuredTokens() {
        let policy = AppPolicy()
        #expect(policy.isStructurallyProtected("https://example.com", inCodeEditor: false))
        #expect(policy.isStructurallyProtected("some_value", inCodeEditor: false))
        #expect(policy.isStructurallyProtected("UIViewController", inCodeEditor: false))
        #expect(policy.isStructurallyProtected("kubectl", inCodeEditor: true))
    }

    @Test func doesNotGloballyDenyCodeEditors() {
        let policy = AppPolicy()
        #expect(policy.isCodeEditor(bundleIdentifier: "com.apple.dt.Xcode"))
        #expect(!policy.isHardDenied(bundleIdentifier: "com.apple.dt.Xcode"))
    }
}
