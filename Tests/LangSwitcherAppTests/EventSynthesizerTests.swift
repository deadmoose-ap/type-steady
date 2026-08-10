import Testing
@testable import LangSwitcherApp

struct EventSynthesizerTests {
    @Test func utf16ChunkingDoesNotSplitEmoji() {
        let source = String(repeating: "а", count: 19) + "🙂" + "б"
        let chunks = EventSynthesizer.chunkUTF16(source, maximumCodeUnits: 20)
        #expect(chunks.map(\.count) == [19, 3])
        let reconstructed = chunks.flatMap { $0 }.withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
        #expect(reconstructed == source)
    }

    @Test func emptyStringProducesNoChunks() {
        #expect(EventSynthesizer.chunkUTF16("", maximumCodeUnits: 20).isEmpty)
    }
}
