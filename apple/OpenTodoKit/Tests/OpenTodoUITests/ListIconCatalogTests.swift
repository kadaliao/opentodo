// The list editor's icons: every symbol exists on this system, and no
// category lists one twice.

#if os(macOS)
import AppKit
#endif
import Testing
@testable import OpenTodoUI

@Suite("ListIconCatalog")
struct ListIconCatalogTests {
    #if os(macOS)
    @Test("every symbol exists")
    func symbolsExist() {
        let missing = ListIconCatalog.symbols.flatMap(\.items).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "missing: \(missing)")
    }
    #endif

    @Test("no repeats within a category, plenty to pick from")
    func noRepeats() {
        for c in ListIconCatalog.symbols + ListIconCatalog.emoji {
            #expect(Set(c.items).count == c.items.count, "\(c.name) repeats")
        }
        let symbols = Set(ListIconCatalog.symbols.flatMap(\.items)).count
        let emoji = Set(ListIconCatalog.emoji.flatMap(\.items)).count
        #expect(symbols >= 200 && emoji >= 200, "\(symbols) symbols, \(emoji) emoji")
    }
}
