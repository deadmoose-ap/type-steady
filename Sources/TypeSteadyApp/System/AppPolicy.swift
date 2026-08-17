import Foundation

struct AppPolicy {
    static let typeSteadyBundleIdentifier = "local.typesteady.app"

    private let passwordManagerPrefixes = [
        "com.1password.",
        "com.agilebits.",
        "com.lastpass.",
        "com.bitwarden."
    ]

    private let codeEditorIdentifiers: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.jetbrains.intellij",
        "com.jetbrains.AppCode",
        "com.jetbrains.CLion",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.PyCharm",
        "com.jetbrains.WebStorm",
        "com.sublimetext.4",
        "com.github.atom"
    ]

    func isHardDenied(bundleIdentifier: String) -> Bool {
        bundleIdentifier == Self.typeSteadyBundleIdentifier ||
            passwordManagerPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    func isCodeEditor(bundleIdentifier: String) -> Bool {
        codeEditorIdentifiers.contains(bundleIdentifier) || bundleIdentifier.hasPrefix("com.jetbrains.")
    }

    func isStructurallyProtected(_ token: String, inCodeEditor: Bool) -> Bool {
        guard !token.isEmpty else { return true }
        let lower = token.lowercased()

        if lower.contains("://") || lower.contains("@") || lower.contains("\\") || lower.contains("/") {
            return true
        }
        if token.contains("_") || token.range(of: #"[A-Za-z][0-9]|[0-9][A-Za-z]"#, options: .regularExpression) != nil {
            return true
        }
        let identifierPatterns = [
            #"^[a-z]+(?:[A-Z][A-Za-z0-9]*)+$"#,
            #"^[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]*)+$"#,
            #"^[A-Z]{2,}(?:[A-Z][a-z0-9]+)+$"#
        ]
        if identifierPatterns.contains(where: {
            token.range(of: $0, options: .regularExpression) != nil
        }) {
            return true
        }
        if inCodeEditor && token.range(of: #"^[A-Za-z][A-Za-z0-9.+#-]{1,31}$"#, options: .regularExpression) != nil {
            let knownCodeTokens: Set<String> = [
                "api", "async", "await", "bool", "class", "const", "enum", "false", "func",
                "git", "html", "http", "https", "int", "json", "kubectl", "let", "nginx",
                "nil", "null", "private", "public", "sql", "ssh", "string", "struct", "swift",
                "true", "var", "void", "xml", "yaml"
            ]
            return knownCodeTokens.contains(lower)
        }
        return false
    }
}
