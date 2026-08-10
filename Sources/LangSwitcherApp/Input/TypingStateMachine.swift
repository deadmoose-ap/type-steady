import Foundation

struct TypingStateMachine {
    private struct PendingAmbiguous: Equatable {
        let key: PhysicalKey
        let currentCharacter: String
        let createdAt: TimeInterval
    }

    private(set) var activeKeys: [PhysicalKey] = []
    private(set) var lastCompleted: CompletedToken?
    private var pendingAmbiguous: PendingAmbiguous?
    private var context: AppContext?

    var hasPendingAmbiguousKey: Bool { pendingAmbiguous != nil }

    mutating func consume(
        key: PhysicalKey,
        currentCharacter: String,
        alternateCharacter: String?,
        context newContext: AppContext,
        timestamp: TimeInterval
    ) -> CompletedToken? {
        if context != nil && context != newContext { invalidate() }
        context = newContext

        guard let first = currentCharacter.first else {
            invalidate()
            return nil
        }

        if first.isWhitespace {
            return finishWithWhitespace(currentCharacter, context: newContext, timestamp: timestamp)
        }

        let currentIsWord = Self.isWordCharacter(first)
        let alternateIsWord = alternateCharacter?.first.map(Self.isWordCharacter) ?? false
        let isAmbiguousPunctuation = first.isPunctuationOrSymbol && alternateIsWord

        if let pending = pendingAmbiguous {
            if currentIsWord || alternateIsWord {
                activeKeys.append(pending.key)
                pendingAmbiguous = nil
            } else {
                let trailingBoundary = first.isPunctuationOrSymbol ? currentCharacter : ""
                return complete(
                    variants: [TokenVariant(keys: activeKeys, boundary: pending.currentCharacter + trailingBoundary)],
                    deletionCount: activeKeys.count + 1 + (trailingBoundary.isEmpty ? 0 : 1),
                    context: newContext,
                    timestamp: timestamp
                )
            }
        }

        if isAmbiguousPunctuation, !activeKeys.isEmpty {
            pendingAmbiguous = PendingAmbiguous(key: key, currentCharacter: currentCharacter, createdAt: timestamp)
            return nil
        }

        if currentIsWord || alternateIsWord {
            activeKeys.append(key)
            return nil
        }

        if first.isPunctuationOrSymbol, !activeKeys.isEmpty {
            return complete(
                variants: [TokenVariant(keys: activeKeys, boundary: currentCharacter)],
                deletionCount: activeKeys.count + 1,
                context: newContext,
                timestamp: timestamp
            )
        }

        invalidate()
        return nil
    }

    mutating func flushAmbiguous(timestamp: TimeInterval) -> CompletedToken? {
        guard let pending = pendingAmbiguous, let context else { return nil }
        pendingAmbiguous = nil
        return complete(
            variants: [TokenVariant(keys: activeKeys, boundary: pending.currentCharacter)],
            deletionCount: activeKeys.count + 1,
            context: context,
            timestamp: timestamp
        )
    }

    mutating func backspace(timestamp: TimeInterval) {
        if pendingAmbiguous != nil {
            pendingAmbiguous = nil
            return
        }
        if !activeKeys.isEmpty {
            activeKeys.removeLast()
            return
        }
        if let lastCompleted,
           timestamp - lastCompleted.completedAt < 5,
           let variant = lastCompleted.variants.first,
           variant.boundary.count == 1 {
            activeKeys = variant.keys
            self.lastCompleted = nil
        } else {
            invalidate()
        }
    }

    mutating func markCorrectionApplied() {
        activeKeys.removeAll(keepingCapacity: true)
        pendingAmbiguous = nil
    }

    mutating func invalidate(preserveLast: Bool = false) {
        activeKeys.removeAll(keepingCapacity: true)
        pendingAmbiguous = nil
        if !preserveLast { lastCompleted = nil }
        context = nil
    }

    private mutating func finishWithWhitespace(
        _ whitespace: String,
        context: AppContext,
        timestamp: TimeInterval
    ) -> CompletedToken? {
        if let pending = pendingAmbiguous {
            pendingAmbiguous = nil
            let variants = [
                TokenVariant(keys: activeKeys, boundary: pending.currentCharacter + whitespace),
                TokenVariant(keys: activeKeys + [pending.key], boundary: whitespace)
            ]
            return complete(
                variants: variants,
                deletionCount: activeKeys.count + 2,
                context: context,
                timestamp: timestamp
            )
        }
        guard !activeKeys.isEmpty else { return nil }
        return complete(
            variants: [TokenVariant(keys: activeKeys, boundary: whitespace)],
            deletionCount: activeKeys.count + 1,
            context: context,
            timestamp: timestamp
        )
    }

    private mutating func complete(
        variants: [TokenVariant],
        deletionCount: Int,
        context: AppContext,
        timestamp: TimeInterval
    ) -> CompletedToken? {
        guard variants.contains(where: { !$0.keys.isEmpty }) else {
            invalidate()
            return nil
        }
        let token = CompletedToken(
            variants: variants.filter { !$0.keys.isEmpty },
            deletionCount: deletionCount,
            context: context,
            completedAt: timestamp
        )
        lastCompleted = token
        activeKeys.removeAll(keepingCapacity: true)
        pendingAmbiguous = nil
        return token
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetterOrNumber || character == "'" || character == "’" || character == "-"
    }
}
