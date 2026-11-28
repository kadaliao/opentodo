// Ported from `app/test/ordering_test.dart`.

import Testing
@testable import OpenTodoDomain

@Suite("ordering")
struct OrderingTests {
    @Test("a move gives only the moved item a number between its neighbours")
    func between() {
        let o: [String: Double] = ["a": 10, "b": 20, "c": 30]
        func of(_ id: String) -> Double { o[id]! }
        // c to the top.
        #expect(planMove(["a", "b", "c"], "c", 0, of) == ["c": 10 - orderStep])
        // a between b and c (the index counts a where it was).
        #expect(planMove(["a", "b", "c"], "a", 2, of) == ["a": 25])
        // a to the end.
        #expect(planMove(["a", "b", "c"], "a", 3, of) == ["a": 30 + orderStep])
        // Dropped where it already is.
        #expect(planMove(["a", "b", "c"], "b", 1, of) == ["b": 20])
    }

    @Test("an item from elsewhere goes in at the index")
    func fromElsewhere() {
        let o: [String: Double] = ["a": 10, "b": 20, "x": 99]
        func of(_ id: String) -> Double { o[id]! }
        #expect(planMove(["a", "b"], "x", 1, of) == ["x": 15])
        #expect(planMove(["a", "b"], "x", 0, of) == ["x": 10 - orderStep])
        #expect(planMove(["a", "b"], "x", 9, of) == ["x": 20 + orderStep])
        #expect(planMove([], "x", 0, of) == ["x": 0])
    }

    @Test("no room between neighbours: the group is numbered again")
    func renumber() {
        let o: [String: Double] = ["a": 5, "b": 5, "c": 5, "x": 0]
        #expect(planMove(["a", "b", "c"], "x", 1, { o[$0]! }) == [
            "a": 5,
            "x": 5 + orderStep,
            "b": 5 + 2 * orderStep,
            "c": 5 + 3 * orderStep,
        ])
        // Halving the same gap again and again ends in a renumbering, never
        // in a wrong order.
        var p: [String: Double] = ["a": 0, "b": 1, "x": 0]
        var list = ["a", "b"]
        for i in 0..<80 {
            let id = "n\(i)"
            p[id] = 0
            let moved = planMove(list, id, 1, { p[$0]! })
            p.merge(moved) { $1 }
            list.insert(id, at: 1)
            let sorted = list.sorted { p[$0]! < p[$1]! }
            #expect(sorted == list)
        }
    }

    // MARK: several at once

    let o: [String: Double] = ["a": 10, "b": 20, "c": 30, "d": 40]
    func of(_ id: String) -> Double { o[id]! }

    @Test("several at once: land together between their new neighbours, in the order given")
    func manyBetween() {
        // a and c moved to after d (index counts them where they are).
        #expect(planMoveMany(["a", "b", "c", "d"], ["a", "c"], 4, of) == ["a": 40 + orderStep, "c": 40 + 2 * orderStep])
        // To the top.
        #expect(planMoveMany(["a", "b", "c", "d"], ["c", "d"], 0, of) == ["c": 10 - 2 * orderStep, "d": 10 - orderStep])
        // Between a and b: thirds of the gap. (Dart also checks the map's
        // key order, d then c; a Swift dictionary has none.)
        let m = planMoveMany(["a", "b", "c", "d"], ["d", "c"], 1, of)
        #expect(Set(m.keys) == ["d", "c"])
        #expect(m["d"]! > 10 && m["d"]! < m["c"]! && m["c"]! < 20)
        // Coming from elsewhere.
        #expect(planMoveMany(["a", "b"], ["x", "y"], 1, of) == ["x": 10.0 + 10.0 / 3, "y": 10.0 + 20.0 / 3])
        #expect(planMoveMany([], ["x", "y"], 0, of) == ["x": 0, "y": orderStep])
    }

    @Test("several at once: already there in that order: nothing to do")
    func manyAlreadyThere() {
        #expect(planMoveMany(["a", "b", "c", "d"], ["b", "c"], 1, of).isEmpty)
        #expect(planMoveMany(["a", "b", "c", "d"], ["b", "c"], 3, of).isEmpty)
        #expect(!planMoveMany(["a", "b", "c", "d"], ["c", "b"], 1, of).isEmpty)
    }

    @Test("several at once: no room: everything numbered again, in the new order")
    func manyRenumber() {
        let tight: [String: Double] = ["a": 1.0, "b": 1.0 + 2.220446049250313e-16, "c": 3.0] // b one step above a
        let m = planMoveMany(["a", "b", "c"], ["c", "x"], 1, { tight[$0] ?? 0 })
        let p = tight.merging(m) { $1 }
        #expect(p.keys.sorted { p[$0]! < p[$1]! } == ["a", "c", "x", "b"])
        #expect(m["a"] == 1.0)
    }
}

// Dragging a task by its handle in a view that wasn't in 自定义 order
// (今天, 四象限): the order shown becomes the order kept.

@Suite("Orders following what's shown")
struct OrdersFollowingTests {
    private func t(_ id: String, _ order: Double, pinned: Bool = false) -> TodoTask {
        TodoTask(id: id, listId: "L", title: id, pinnedAt: pinned ? 1 : nil, sortOrder: order)
    }

    @Test("the values they have, handed out in the order shown")
    func reuse() {
        let shown = [t("c", 3000), t("a", 1000), t("b", 2000)]
        #expect(ordersFollowing(shown) == ["c": 1000, "a": 2000, "b": 3000])
        #expect(ordersFollowing([t("a", 1), t("b", 2)]).isEmpty)
    }

    @Test("ties are nudged apart")
    func ties() {
        #expect(ordersFollowing([t("a", 5), t("b", 5), t("c", 5)]) == ["b": 6, "c": 7])
    }

    @Test("a move stays among the pinned or the unpinned")
    func pinned() {
        let shown = [t("p", 9, pinned: true), t("a", 1), t("b", 2)]
        #expect(moving(shown, "b", to: 0).map(\.id) == ["p", "b", "a"])
        #expect(moving(shown, "p", to: 2).map(\.id) == ["p", "a", "b"])
        #expect(moving(shown, "a", to: 2).map(\.id) == ["p", "b", "a"])
    }
}
