import Foundation

struct LocalLexicon: Sendable {
    private let common: [LanguageCode: Set<String>]
    private let extended: [LanguageCode: Set<String>]

    init(bundle: Bundle? = nil) {
        let bundle = bundle ?? Self.defaultBundle
        common = [
            .english: Self.load("en_common", bundle: bundle),
            .russian: Self.load("ru_common", bundle: bundle)
        ]
        extended = [
            .english: Self.load("en_extended", bundle: bundle),
            .russian: Self.load("ru_extended", bundle: bundle)
        ]
    }

    /// SwiftPM's generated `Bundle.module` accessor expects its resource bundle
    /// next to `Bundle.main`. A packaged macOS application must keep resources in
    /// `Contents/Resources`, so resolve that standard location before falling
    /// back to SwiftPM's build-directory lookup used by `swift run` and tests.
    private static var defaultBundle: Bundle {
        if let resourcesURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourcesURL
                .appendingPathComponent("TypeSteady_TypeSteadyApp.bundle", isDirectory: true)
            if let packagedBundle = Bundle(url: packagedBundleURL) {
                return packagedBundle
            }
        }
        return .module
    }

    init(common: [LanguageCode: Set<String>], extended: [LanguageCode: Set<String>] = [:]) {
        self.common = common
        self.extended = extended
    }

    func contains(_ word: String, language: LanguageCode) -> Bool {
        let normalized = normalize(word)
        return common[language, default: []].contains(normalized) ||
            extended[language, default: []].contains(normalized)
    }

    func score(_ word: String, language: LanguageCode) -> Double {
        let normalized = normalize(word)
        if common[language, default: []].contains(normalized) { return 6.0 }
        if extended[language, default: []].contains(normalized) { return 4.5 }
        return 0
    }

    private func normalize(_ word: String) -> String {
        word.lowercased().precomposedStringWithCanonicalMapping
    }

    private static func load(_ name: String, bundle: Bundle) -> Set<String> {
        let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Dictionaries")
            ?? bundle.url(forResource: name, withExtension: "txt")
        guard let url,
              let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }
}
