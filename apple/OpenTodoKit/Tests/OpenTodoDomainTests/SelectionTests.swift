// Ported from the group "the selection" of `app/test/selection_test.dart`.
// Its third test ("a new view starts afresh") is about the state layer
// clearing the selection when the view changes; here only `clear` is
// checked. The widget tests of that file (the panel, the phone's bar) are
// for the UI; the clicks they make are checked through `tapTask` below.

import Testing
@testable import OpenTodoDomain

@Suite("selection")
struct SelectionTests {
    @Test("⌘-click brings the open task along; again takes one out")
    func toggle() {
        var s = TaskSelection()
        s.toggle("b", current: "a")
        #expect(s.ids == ["a", "b"])
        s.toggle("a")
        #expect(s.ids == ["b"])
        s.toggle("b")
        #expect(!s.active)
    }

    @Test("Shift-click takes the range from the last pick, either way")
    func range() {
        let order = ["a", "b", "c", "d", "e"]
        var s = TaskSelection()
        s.toggle("b")
        s.extend(to: "d", in: order)
        #expect(s.ids == ["b", "c", "d"])
        s.extend(to: "a", in: order)
        #expect(s.ids == ["a", "b", "c", "d"])
        s.clear()
        // Nothing picked yet: from the task open in the detail.
        s.extend(to: "c", in: order, current: "e")
        #expect(s.ids == ["c", "d", "e"])
    }

    @Test("select all, and clearing starts afresh")
    func selectAllAndClear() {
        var s = TaskSelection()
        s.selectAll(["a", "b"])
        #expect(s.ids == ["a", "b"])
        #expect(s.anchor == "a")
        s.clear()
        #expect(s.ids.isEmpty && s.anchor == nil)
        s.start("x")
        #expect(s.ids == ["x"] && s.anchor == "x")
    }

    // The clicks of the widget tests ("desktop: ⌘-click and Shift-click
    // pick tasks", "phone: 多选 from the menu; taps pick").

    @Test("desktop clicks: plain opens, ⌘ and Shift pick")
    func desktopClicks() {
        // The inbox shows 丁 丙 乙 甲.
        let order = ["丁", "丙", "乙", "甲"]
        var s = TaskSelection()
        #expect(tapTask("丁", selection: &s, order: order, current: nil, touch: false) == "丁")
        #expect(!s.active)
        #expect(tapTask("乙", selection: &s, order: order, current: "丁", modifiers: .command, touch: false) == nil)
        #expect(s.ids == ["丁", "乙"])
        // Shift-click from 乙 to 甲 adds 甲; ⌘-click adds 丙.
        tapTask("甲", selection: &s, order: order, current: "丁", modifiers: .shift, touch: false)
        #expect(s.ids.count == 3)
        tapTask("丙", selection: &s, order: order, current: "丁", modifiers: .command, touch: false)
        #expect(s.ids.count == 4)
        // A plain click stops picking and opens.
        #expect(tapTask("甲", selection: &s, order: order, current: "丁", touch: false) == "甲")
        #expect(!s.active)
    }

    @Test("phone: once picking, a tap picks instead of opening")
    func phoneTaps() {
        var s = TaskSelection()
        #expect(tapTask("甲", selection: &s, order: [], current: nil, touch: true) == "甲")
        s.start("甲")
        #expect(tapTask("丙", selection: &s, order: [], current: nil, touch: true) == nil)
        #expect(s.ids == ["甲", "丙"])
        tapTask("甲", selection: &s, order: [], current: nil, touch: true)
        tapTask("丙", selection: &s, order: [], current: nil, touch: true)
        #expect(!s.active)
    }
}
