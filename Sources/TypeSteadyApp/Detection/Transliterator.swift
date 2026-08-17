import Foundation

struct Transliterator {
    private let mapping: [String: [String]] = [
        "shch": ["щ"], "sch": ["щ"], "yo": ["ё"], "jo": ["ё"],
        "zh": ["ж"], "kh": ["х"], "ts": ["ц"], "ch": ["ч"],
        "sh": ["ш"], "yu": ["ю"], "ju": ["ю"], "ya": ["я"],
        "ja": ["я"], "ye": ["е"], "iy": ["ий"],
        "a": ["а"], "b": ["б"], "c": ["к", "с"], "d": ["д"],
        "e": ["е", "э"], "f": ["ф"], "g": ["г"], "h": ["х"],
        "i": ["и", "й"], "j": ["й", "ж"], "k": ["к"], "l": ["л"],
        "m": ["м"], "n": ["н"], "o": ["о"], "p": ["п"],
        "q": ["к"], "r": ["р"], "s": ["с"], "t": ["т"],
        "u": ["у"], "v": ["в"], "w": ["в"], "x": ["кс"],
        "y": ["ы", "й"], "z": ["з"]
    ]

    func candidates(for source: String, limit: Int = 64) -> [String] {
        guard source.unicodeScalars.allSatisfy({ $0.isASCII }) else { return [] }
        let lowercase = source.lowercased()
        var beam: [(index: String.Index, value: String)] = [(lowercase.startIndex, "")]
        var completed: [String] = []

        while !beam.isEmpty && completed.count < limit {
            let state = beam.removeFirst()
            if state.index == lowercase.endIndex {
                completed.append(applyCase(of: source, to: state.value))
                continue
            }

            var expansions: [(String.Index, String)] = []
            for length in stride(from: 4, through: 1, by: -1) {
                guard let end = lowercase.index(state.index, offsetBy: length, limitedBy: lowercase.endIndex) else { continue }
                let chunk = String(lowercase[state.index..<end])
                guard let replacements = mapping[chunk] else { continue }
                expansions.append(contentsOf: replacements.map { (end, state.value + $0) })
            }

            for expansion in expansions.prefix(8) {
                beam.append((expansion.0, expansion.1))
            }
            if beam.count > limit * 4 {
                beam.removeLast(beam.count - limit * 4)
            }
        }
        return Array(Set(completed)).prefix(limit).map { $0 }
    }

    private func applyCase(of source: String, to target: String) -> String {
        if source == source.uppercased() { return target.uppercased() }
        if source.first?.isUppercase == true {
            return target.prefix(1).uppercased() + target.dropFirst()
        }
        return target
    }
}
