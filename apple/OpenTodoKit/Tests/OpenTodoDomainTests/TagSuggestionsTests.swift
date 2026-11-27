import Testing
@testable import OpenTodoDomain

@Suite("tag suggestions")
struct TagSuggestionsTests {
    private let tags = ["OpenTodo", "homework", "工作", "加工", "Work", "豆瓣小工具"]

    @Test("nothing typed: every tag, in order")
    func empty() {
        #expect(tagSuggestions(tags, typed: "") == tags)
        #expect(tagSuggestions(tags, typed: "  # ") == tags)
    }

    @Test("found ignoring case and a leading #, those starting with it first")
    func typed() {
        #expect(tagSuggestions(tags, typed: "work") == ["Work", "homework"])
        #expect(tagSuggestions(tags, typed: "#工") == ["工作", "加工", "豆瓣小工具"])
        #expect(tagSuggestions(tags, typed: "OPEN") == ["OpenTodo"])
        #expect(tagSuggestions(tags, typed: "周报").isEmpty)
    }

    @Test("Chinese in pinyin, two letters at least")
    func pinyin() {
        #expect(tagSuggestions(tags, typed: "gz") == ["工作"])
        #expect(tagSuggestions(tags, typed: "dbx") == ["豆瓣小工具"])
        #expect(!tagSuggestions(tags, typed: "g").contains("工作"))
    }
}
