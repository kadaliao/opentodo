// Ported from `app/test/search_test.dart`.

import Testing
@testable import OpenTodoDomain

private func item(_ taskId: String, _ title: String, done: Bool = false) -> ChecklistItem {
    ChecklistItem(id: "\(taskId)-\(title)", taskId: taskId, title: title, done: done, dirty: false)
}

private func filter(_ id: String, _ name: String) -> TaskFilter {
    TaskFilter(id: id, name: name, rule: "{}", dirty: false)
}

@Suite("search")
struct SearchTests {
    @Test("terms: split on spaces, lower case, # dropped")
    func terms() {
        #expect(searchTerms("  周报  Q3 #工作 # ") == ["周报", "q3", "工作"])
        #expect(searchTerms("   ").isEmpty)
    }

    @Test("ranges are merged and ignore case")
    func ranges() {
        #expect(findRanges("Weekly report, weekly", ["weekly"]) == [0..<6, 15..<21])
        #expect(findRanges("abcdef", ["abc", "cde"]) == [0..<5])
        #expect(findRanges("晨会会议", ["会"]) == [1..<3])
        #expect(findRanges("无", ["x"]).isEmpty)
    }

    @Test("every word has to be somewhere: title, notes, subtasks or tags")
    func everyWord() {
        let tasks = [
            makeTask("写周报", content: "本周数据"),
            makeTask("开会", tags: ["周报"]),
            makeTask("整理", content: ""),
            makeTask("季度总结"),
        ]
        let checklist = ["整理": [item("整理", "周报附件")]]
        let r = search("周报", tasks: tasks, checklist: checklist)
        #expect(Set(r.tasks.map(\.task.title)).isSuperset(of: ["写周报", "开会", "整理"]))
        #expect(r.tasks.count == 3)
        // Title matches first.
        #expect(r.tasks.first?.task.title == "写周报")

        let both = search("周报 数据", tasks: tasks, checklist: checklist)
        #expect(both.tasks.map(\.task.title) == ["写周报"])
        #expect(both.tasks.first?.titleRanges == [1..<3])
        #expect(both.tasks.first?.snippet == "本周数据")
        #expect(both.tasks.first?.snippetRanges == [2..<4])

        let sub = search("附件", tasks: tasks, checklist: checklist).tasks
        #expect(sub.count == 1)
        #expect(sub.first?.snippet == "☐ 周报附件")
        #expect(sub.first?.snippetRanges == [4..<6])

        let tag = search("#周报", tasks: tasks).tasks.first { $0.task.title == "开会" }
        #expect(tag?.snippet == "#周报")
    }

    @Test("open before finished, trash left out, newest first")
    func order() {
        let tasks = [
            makeTask("周报 旧", status: .done),
            makeTask("周报 一"),
            makeTask("周报 二"),
            makeTask("周报 删了", trashedAt: 1),
        ]
        #expect(search("周报", tasks: tasks).tasks.map(\.task.title) == ["周报 二", "周报 一", "周报 旧"])
    }

    @Test("notes are cut around the match")
    func cut() throws {
        let long = String(repeating: "甲", count: 40) + "关键词" + String(repeating: "乙", count: 100)
        let hits = search("关键词", tasks: [makeTask("标题", content: long)]).tasks
        #expect(hits.count == 1)
        let snippet = try #require(hits.first?.snippet)
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(String(decoding: Array(snippet.utf16)[1..<13], as: UTF16.self) == String(repeating: "甲", count: 12))
        #expect(hits.first?.snippetRanges == [13..<16])
    }

    @Test("lists, tags and filters by name; long results are capped")
    func names() {
        let r = search(
            "工作",
            tasks: (0..<5).map { makeTask("工作\($0)") },
            lists: [list("a", "工作"), list("b", "家里")],
            tags: ["工作", "个人"],
            filters: [filter("f", "本周工作")],
            taskLimit: 3
        )
        #expect(r.lists.map(\.name) == ["工作"])
        #expect(r.tags == ["工作"])
        #expect(r.filters.map(\.name) == ["本周工作"])
        #expect(r.tasks.count == 3)
        #expect(r.moreTasks == 2)
        #expect(search(" ", tasks: [makeTask("x")]).isEmpty)
    }

    @Test("titles and names can be typed in pinyin")
    func pinyin() {
        let tasks = [makeTask("写周报"), makeTask("周会"), makeTask("report", content: "周报")]
        let r = search("zb", tasks: tasks, lists: [list("a", "工作")], tags: ["周报"])
        #expect(r.tasks.map(\.task.title) == ["写周报", "report"]) // Dart: ["写周报"]
        #expect(r.tasks.first?.titleRanges == [1..<3])
        #expect(r.tags == ["周报"])
        #expect(search("gz", tasks: [], lists: [list("a", "工作")]).lists.map(\.name) == ["工作"])
        // Mixed with a word as typed; one letter alone isn't read as pinyin.
        #expect(search("zhou 写", tasks: tasks).tasks.map(\.task.title) == ["写周报"])
        #expect(search("z", tasks: tasks).tasks.isEmpty)
        // The Dart version doesn't look for pinyin in notes (it found only
        // 写周报 above, and highlighted only "zb" here); the Swift version
        // does, see SearchExtrasTests.
        #expect(search("zb", tasks: [makeTask("x", content: "zb 周报")]).tasks.map(\.snippetRanges) == [[0..<2, 3..<5]])
    }
}
