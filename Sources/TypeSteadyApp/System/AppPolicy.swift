import Foundation

struct AppPolicy {
    static let typeSteadyBundleIdentifier = "local.typesteady.app"

    // B5: раньше эти паттерны передавались строками в token.range(of:options:.regularExpression),
    // который компилирует NSRegularExpression заново на КАЖДЫЙ вызов — а isStructurallyProtected
    // вызывается на каждый завершённый токен. Предкомпилированы один раз в static let.
    // NSRegularExpression — потокобезопасный неизменяемый (immutable) тип, поэтому общий
    // static-экземпляр безопасен для конкурентного использования.
    //
    // range(of:options:.regularExpression) ищет ПОДСТРОКУ, а не полное совпадение — семантика
    // сохранена 1:1, включая уже расставленные якоря ^/$ там, где они были в исходных паттернах.
    private static let mixedAlnumPattern = try! NSRegularExpression(pattern: #"[A-Za-z][0-9]|[0-9][A-Za-z]"#)
    private static let lowerCamelPattern = try! NSRegularExpression(pattern: #"^[a-z]+(?:[A-Z][A-Za-z0-9]*)+$"#)
    private static let upperCamelPattern = try! NSRegularExpression(pattern: #"^[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]*)+$"#)
    private static let screamingCamelPattern = try! NSRegularExpression(pattern: #"^[A-Z]{2,}(?:[A-Z][a-z0-9]+)+$"#)
    private static let codeTokenPattern = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9.+#-]{1,31}$"#)
    private static let identifierPatterns = [lowerCamelPattern, upperCamelPattern, screamingCamelPattern]

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
        if token.contains("_") || Self.matches(Self.mixedAlnumPattern, in: token) {
            return true
        }
        if Self.identifierPatterns.contains(where: { Self.matches($0, in: token) }) {
            return true
        }
        if inCodeEditor && Self.matches(Self.codeTokenPattern, in: token) {
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

    /// Эквивалент `token.range(of: pattern, options: .regularExpression) != nil`, но по
    /// предкомпилированному NSRegularExpression — ищет ПОДСТРОКУ, не требует полного совпадения.
    private static func matches(_ regex: NSRegularExpression, in token: String) -> Bool {
        regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) != nil
    }
}
