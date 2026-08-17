import Testing
@testable import TypeSteadyApp

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

    @Test func hardDeniesSupportedPasswordManagers() {
        let policy = AppPolicy()
        #expect(policy.isHardDenied(bundleIdentifier: "com.1password.desktop"))
        #expect(policy.isHardDenied(bundleIdentifier: "com.agilebits.onepassword7"))
        #expect(policy.isHardDenied(bundleIdentifier: "com.lastpass.LastPass"))
        #expect(policy.isHardDenied(bundleIdentifier: "com.bitwarden.desktop"))
        #expect(!policy.isHardDenied(bundleIdentifier: "com.example.editor"))
    }

    @Test func hardDeniesTypeSteadySettingsItself() {
        let policy = AppPolicy()
        #expect(policy.isHardDenied(bundleIdentifier: "local.typesteady.app"))
    }

    @Test func recognizesEditorFamilies() {
        let policy = AppPolicy()
        #expect(policy.isCodeEditor(bundleIdentifier: "com.microsoft.VSCode"))
        #expect(policy.isCodeEditor(bundleIdentifier: "com.jetbrains.Rider"))
        #expect(policy.isCodeEditor(bundleIdentifier: "com.sublimetext.4"))
        #expect(!policy.isCodeEditor(bundleIdentifier: "com.apple.TextEdit"))
    }

    @Test func protectsPathsEmailsMixedTokensAndIdentifiers() {
        let policy = AppPolicy()
        for token in [
            "user@example.com", "/usr/local/bin", #"C:\\Temp\\file"#,
            "value2", "2value", "lowerCamel", "PascalCase", "APIClient"
        ] {
            #expect(policy.isStructurallyProtected(token, inCodeEditor: false), "Expected \(token) to be protected")
        }
        #expect(!policy.isStructurallyProtected("ordinary", inCodeEditor: false))
        #expect(!policy.isStructurallyProtected("ordinary", inCodeEditor: true))
    }
}
