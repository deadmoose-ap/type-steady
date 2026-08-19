import Foundation

struct AppPolicy {
    static let typeSteadyBundleIdentifier = "local.typesteady.app"

    // C7: сравнение регистронезависимое — normalize в isHardDenied приводит входной
    // bundleIdentifier к нижнему регистру, поэтому и коллекции здесь должны быть заранее
    // приведены к нижнему регистру, иначе Set.contains/hasPrefix молча перестанут совпадать.
    private let passwordManagerPrefixes = [
        "com.1password.",
        "com.agilebits.",
        "com.lastpass.",
        "com.bitwarden.",
        "com.dashlane.",
        "com.keepersecurity.",
        "com.nordpass.",
        "me.proton.pass.",
        "org.keepassxc.",
        "io.enpass.",
        "com.strongbox."
    ]

    // Точные идентификаторы системных компонентов Apple, а не префиксы: префикс "com.apple."
    // случайно заблокировал бы все приложения Apple, включая Safari и TextEdit.
    // Приведены к нижнему регистру заранее — исходные ID (com.apple.Passwords,
    // com.apple.SecurityAgent) используют смешанный регистр, а сравнение в isHardDenied
    // регистронезависимое (см. C7).
    private let exactPasswordManagerIdentifiers: Set<String> = [
        // Штатное приложение «Пароли» в macOS 15+ — самый частый случай.
        "com.apple.passwords",
        "com.apple.keychainaccess",
        // Системные диалоги авторизации.
        "com.apple.securityagent",
        "com.apple.loginwindow"
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
        // C7: нормализуем регистр здесь, а не полагаемся на то, что вызывающий код всегда
        // передаёт каноническую форму — иначе будущее приведение к нижнему регистру на
        // пути вызова молча отключит hard deny для системных компонентов Apple.
        let normalized = bundleIdentifier.lowercased()
        return normalized == Self.typeSteadyBundleIdentifier.lowercased() ||
            exactPasswordManagerIdentifiers.contains(normalized) ||
            passwordManagerPrefixes.contains { normalized.hasPrefix($0) }
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
