import Foundation

/// Helpers for making arbitrary user text fit the menu bar.
enum TitleFormatting {
    /// Longest title we will show, counted in extended grapheme clusters.
    static let maxLength = 40

    /// Normalize text for display in the menu bar: single line, trimmed, and
    /// truncated so it stays "short". Whitespace-only input falls back to "...".
    static func sanitize(_ input: String) -> String {
        let oneLine = input.map { character -> Character in
            switch character {
            case "\n", "\r", "\t": return " "
            default: return character
            }
        }

        let trimmed = String(oneLine).trimmingCharacters(in: .whitespaces)
        let capped = String(trimmed.prefix(maxLength))
        return capped.isEmpty ? "..." : capped
    }
}
