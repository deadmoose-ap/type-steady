import Foundation

/// Normalized user-maintained terms used by the recognition policy.
///
/// Automatic correction is evaluated one completed token at a time. To make a
/// multi-word reserved term effective before its last word is typed, every word
/// component of the term is protected as well as the complete normalized line.
struct UserTermRules: Equatable, Sendable {
    let entries: Set<String>
    let protectedTokens: Set<String>

    init(_ source: String) {
        let entries = Set(source
            .components(separatedBy: .newlines)
            .map(Self.normalize)
            .filter { !$0.isEmpty })
        self.entries = entries
        protectedTokens = Set(entries.flatMap(Self.tokens))
    }

    func contains(_ token: String) -> Bool {
        let normalized = Self.normalize(token)
        return entries.contains(normalized) || protectedTokens.contains(normalized)
    }

    static func normalize(_ source: String) -> String {
        source
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func tokens(in term: String) -> [String] {
        var result: [String] = []
        var current = ""

        func finishToken() {
            let token = current.trimmingCharacters(in: CharacterSet(charactersIn: "-'’"))
            if !token.isEmpty { result.append(token) }
            current.removeAll(keepingCapacity: true)
        }

        for character in term {
            if character.isLetterOrNumber {
                current.append(character)
            } else if character == "-" || character == "'" || character == "’" {
                if !current.isEmpty { current.append(character) }
            } else {
                finishToken()
            }
        }
        finishToken()
        return result
    }
}
