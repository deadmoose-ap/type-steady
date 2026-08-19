import AppKit
import Testing
@testable import TypeSteadyApp

// B1 §A: с переходом транзакции коррекции на async/await между шагами появились точки
// приостановки, которых не было при синхронном apply() — второй хоткей или второе
// завершённое слово теоретически могли бы запустить параллельную транзакцию поверх ещё не
// завершившейся. CorrectionCoordinator отклоняет такую попытку флагом `transactionInProgress`.
//
// Прогнать полноценную гонку двух настоящих параллельных Task с реальным event tap и AX
// здесь недостижимо детерминированно (нет управляемого способа удержать первую транзакцию
// «в полёте» ровно до момента, когда стартует вторая, без реального устройства/переключения
// раскладок) — поэтому тест воспроизводит защищаемое условие напрямую: выставляет
// `transactionInProgress = true` (доступен через @testable) и проверяет, что `apply()`
// отклоняет вызов, не трогая gate/раскладку, вместо того чтобы гнаться за таймингом.
@MainActor
struct CorrectionCoordinatorReentrancyTests {
    @Test func applyRejectsWhileAnotherTransactionIsInProgress() async throws {
        let frontmost = try #require(NSWorkspace.shared.frontmostApplication)
        let context = AppContext(
            processIdentifier: frontmost.processIdentifier,
            bundleIdentifier: frontmost.bundleIdentifier ?? "test"
        )

        let tap = InputEventTap()
        let layouts = LayoutCatalog()
        let logger = DiagnosticLogger()
        let coordinator = CorrectionCoordinator(eventTap: tap, layoutCatalog: layouts, logger: logger)

        // Раскладки намеренно не заполнены (layouts.refresh(settings:) не вызывался) — даже
        // если бы реентерабельность не сработала, selectLayout(id:) откажет сама, не выполняя
        // никакой реальной синтезированной клавиатуры. Это не то, что тест проверяет, но
        // гарантирует отсутствие побочных эффектов на реальном фокусе, если защита сломается.
        coordinator.transactionInProgress = true

        let proposal = CorrectionProposal(
            original: "ghbdtn",
            replacement: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            confidence: 1,
            kind: .layout
        )
        let variant = TokenVariant(keys: [], boundary: " ")

        let result = await coordinator.apply(
            proposal: proposal,
            variant: variant,
            deletionCount: 0,
            sourceLayoutID: "does-not-matter",
            targetLayoutID: "does-not-matter",
            context: context
        )

        #expect(result == false)
        // Флаг должен остаться нетронутым — отклонённый вызов не имеет права сбросить
        // состояние транзакции, которая ему не принадлежит.
        #expect(coordinator.transactionInProgress == true)
    }

    @Test func applySucceedsAfterPreviousTransactionFlagIsCleared() async throws {
        let frontmost = try #require(NSWorkspace.shared.frontmostApplication)
        let context = AppContext(
            processIdentifier: frontmost.processIdentifier,
            bundleIdentifier: frontmost.bundleIdentifier ?? "test"
        )

        let tap = InputEventTap()
        let layouts = LayoutCatalog()
        let logger = DiagnosticLogger()
        let coordinator = CorrectionCoordinator(eventTap: tap, layoutCatalog: layouts, logger: logger)

        // Флаг не выставлен — apply() обязана дойти до реального шага (провалиться на
        // отсутствующей раскладке, а не на реентерабельности), и обязана сама сбросить флаг
        // на выходе, не оставляя его "залипшим" для следующего вызова.
        let result = await coordinator.apply(
            proposal: CorrectionProposal(
                original: "ghbdtn",
                replacement: "привет",
                sourceLanguage: .english,
                targetLanguage: .russian,
                confidence: 1,
                kind: .layout
            ),
            variant: TokenVariant(keys: [], boundary: " "),
            deletionCount: 0,
            sourceLayoutID: "does-not-matter",
            targetLayoutID: "does-not-matter",
            context: context
        )

        #expect(result == false) // раскладка не найдена — это ожидаемо, не реентерабельность.
        #expect(coordinator.transactionInProgress == false)
    }
}
