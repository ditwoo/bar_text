import Testing
@testable import BarText

@Suite("TitleFormatting.sanitize")
struct TitleFormattingTests {
    @Test func trimsWhitespace() {
        #expect(TitleFormatting.sanitize("  hello  ") == "hello")
    }

    @Test func flattensNewlinesAndTabs() {
        #expect(TitleFormatting.sanitize("a\nb\tc") == "a b c")
    }

    @Test func truncatesToMaxLength() {
        let long = String(repeating: "x", count: 100)
        #expect(TitleFormatting.sanitize(long).count == 40)
    }

    @Test func whitespaceOnlyFallsBackToEllipsis() {
        #expect(TitleFormatting.sanitize("   \n\t  ") == "...")
    }

    @Test func emptyInputFallsBackToEllipsis() {
        #expect(TitleFormatting.sanitize("") == "...")
    }
}
