import Foundation

struct PhysicalKey: Hashable, Sendable {
    let keyCode: UInt16
    let shift: Bool
    let capsLock: Bool
}

struct AppContext: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String

    static let unknown = AppContext(processIdentifier: 0, bundleIdentifier: "unknown")
}

enum LanguageCode: String, CaseIterable, Sendable {
    case english = "en"
    case russian = "ru"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

struct TokenVariant: Equatable, Sendable {
    let keys: [PhysicalKey]
    let boundary: String
}

struct CompletedToken: Equatable, Sendable {
    let variants: [TokenVariant]
    let deletionCount: Int
    let context: AppContext
    let completedAt: TimeInterval
}

struct CorrectionProposal: Equatable, Sendable {
    enum Kind: String, Sendable {
        case layout
        case transliteration
        case forced
    }

    let original: String
    let replacement: String
    let sourceLanguage: LanguageCode
    let targetLanguage: LanguageCode
    let confidence: Double
    let kind: Kind
}

struct LastCorrection: Sendable {
    let original: String
    let replacement: String
    let boundary: String
    let sourceLayoutID: String
    let targetLayoutID: String
    let context: AppContext
    let completedAt: TimeInterval
}

extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    var isWhitespace: Bool {
        unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    var isPunctuationOrSymbol: Bool {
        unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }
}
