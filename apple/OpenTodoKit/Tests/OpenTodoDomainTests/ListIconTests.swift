// A list's icon as its `emoji` column holds it (ListIcon.swift).

import OpenTodoDomain
import Testing

@Suite("ListIcon")
struct ListIconTests {
    @Test("emoji, symbol, nothing")
    func parse() {
        #expect(ListIcon(stored: "💼") == .emoji("💼"))
        #expect(ListIcon(stored: "sf:briefcase") == .symbol("briefcase"))
        #expect(ListIcon(stored: nil) == nil)
        #expect(ListIcon(stored: "") == nil)
        #expect(ListIcon(stored: "sf:") == nil)
        #expect(ListIcon.symbol("cart").stored == "sf:cart")
        #expect(ListIcon.emoji("AI").stored == "AI")
    }

    @Test("typed in: trimmed, two characters at most")
    func custom() {
        #expect(ListIcon.custom("  AI ") == .emoji("AI"))
        #expect(ListIcon.custom("工作计划") == .emoji("工作"))
        #expect(ListIcon.custom("👨‍👩‍👧x y") == .emoji("👨‍👩‍👧x"))
        #expect(ListIcon.custom("a b") == .emoji("a"))
        #expect(ListIcon.custom("   ") == nil)
    }

    @Test("text before a name: emoji only")
    func textEmoji() {
        #expect(TaskList(id: "l", emoji: "🛒").textEmoji == "🛒")
        #expect(TaskList(id: "l", emoji: "sf:cart").textEmoji == nil)
        #expect(TaskList(id: "l", emoji: "sf:cart").icon == .symbol("cart"))
        #expect(TaskList(id: "l").textEmoji == nil)
    }
}
