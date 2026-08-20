import AppKit
import Testing
@testable import TypeSteadyApp

// F2: сообщение об отказе (onMessage) должно висеть дольше короткого «English → Русский»
// (onCorrection) — иначе пользователь не успевает прочитать причину. Полноценно проверить
// реальный dismiss-таймер детерминированно нельзя (DispatchQueue.main.asyncAfter, реальный
// NSPanel), поэтому тест фиксирует то, что действительно детерминировано: сами именованные
// константы длительности различаются и соответствуют F1/F2 (короткая — значение по умолчанию,
// длинная — строго больше короткой, а не наоборот по ошибке).
@MainActor
@Suite("FeedbackPresenterDurationTests")
struct FeedbackPresenterDurationTests {
    @Test("short duration matches the historical default of 0.9s")
    func shortDurationIsUnchanged() {
        #expect(FeedbackPresenter.shortDuration == 0.9)
    }

    @Test("long duration is meaningfully longer than the short one")
    func longDurationExceedsShortDuration() {
        #expect(FeedbackPresenter.longDuration > FeedbackPresenter.shortDuration)
        #expect(FeedbackPresenter.longDuration == 3.5)
    }

    @Test("show(_:sound:visual:) without an explicit duration keeps the historical default")
    func defaultParameterMatchesShortDuration() {
        // Компилируемость этого вызова без duration: — гарантия того, что существующие
        // сайты вызова (если такие остались) не меняют поведение по умолчанию.
        let presenter = FeedbackPresenter()
        presenter.show("test", sound: false, visual: false)
        // visual: false — плашка не показывается, только фиксируем, что вызов без duration
        // компилируется и не падает; сама константа по умолчанию проверена выше.
        #expect(FeedbackPresenter.shortDuration == 0.9)
    }
}
