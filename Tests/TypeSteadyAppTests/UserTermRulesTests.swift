import Testing
@testable import TypeSteadyApp

struct UserTermRulesTests {
    @Test func normalizesCaseWhitespaceAndUnicode() {
        let rules = UserTermRules("  CAFÉ   Noir  \n")

        #expect(rules.entries == ["café noir"])
        #expect(rules.contains("cafe\u{301}"))
        #expect(rules.contains("NOIR"))
    }

    @Test func protectsEveryComponentOfMultiwordTerms() {
        let rules = UserTermRules("TypeSteady API-client\nOpenAI/Codex")

        #expect(rules.contains("typesteady"))
        #expect(rules.contains("API-client"))
        #expect(rules.contains("openai"))
        #expect(rules.contains("codex"))
        #expect(!rules.contains("unrelated"))
    }

    @Test func ignoresBlankLinesAndTrimsConnectors() {
        let rules = UserTermRules("\n  \n'quoted'\n--term--\n")

        #expect(rules.entries.count == 2)
        #expect(rules.contains("quoted"))
        #expect(rules.contains("term"))
    }
}
