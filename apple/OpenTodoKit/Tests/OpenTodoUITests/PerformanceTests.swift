// How long the app's data path takes on a big account (PerfFixture: 5000
// tasks, 3500 finished, 8000 subtasks). Each measure prints
// `PERF <what>: median … ms`. The limits are loose (a debug build, a busy
// machine) but low enough to catch something going quadratic; the database
// round trips depend on the machine too much and are only printed.
//
// What runs on every data change or every frame should stay well under a
// frame (16 ms) in a release build.
//
// The full measuring suite takes a few seconds of CPU and would slow the
// time-sensitive tests running beside it, so it runs only when asked:
//
//     OT_PERF=1 swift test --filter PerformanceTests 2>&1 | grep PERF
//     OT_PERF=1 swift test -c release -j 4 -Xswiftc -enable-testing --filter PerformanceTests 2>&1 | grep PERF
//
// `PerformanceGuard` always runs: each costly path once, with limits that
// only a return to the old quadratic ways would break.

import Foundation
import GRDB
@testable import OpenTodoData
@testable import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private func makeModel() throws -> AppModel {
    let db = try AppDatabase.inMemory()
    let repo = TaskRepo(db, clock: { perfNow.date(in: perfZone) }, timeZone: perfZone)
    let model = AppModel(repo: repo, settings: LocalSettings(db), now: perfNow)
    model.receive(perfData)
    return model
}

/// What a list's body asks the model for each row (TaskListView.rows).
private func rowWork(_ m: AppModel, _ view: ViewRef) -> Int {
    var n = 0
    for s in m.sections(for: view) {
        for t in s.tasks {
            _ = m.listsById[t.listId]
            _ = m.showsList(in: view)
            n += m.checklistProgress(of: t.id).total
        }
    }
    return n
}

/// The views the sidebar counts (ViewsList): the smart lists, every list,
/// every filter, every tag.
private func sidebarViews(_ m: AppModel) -> [ViewRef] {
    [.smart(.today), .smart(.tomorrow), .smart(.next7), .smart(.inbox)]
        + m.lists.map { .list($0.id) } + m.filters.map { .filter($0.id) } + m.tags.map { .tag($0) }
}

/// Whether the full measuring suite runs (`OT_PERF=1`).
nonisolated private let measuring = ProcessInfo.processInfo.environment["OT_PERF"] != nil

@Suite("performance guard")
struct PerformanceGuard {
    @Test("the costly paths stay far from quadratic")
    func guardrails() throws {
        let m = try makeModel()
        let clock = ContinuousClock()
        func ms(_ body: () -> Void) -> Double {
            let d = clock.measure(body)
            return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        // Before the snapshot cache and the index sort these were 2948 ms,
        // 7700 ms, 81 ms and 29 ms (debug).
        #expect(ms { _ = rowWork(m, .list(perfBigList)) } < 500)
        m.receive(perfData)
        #expect(ms { _ = rowWork(m, .smart(.completed)) } < 1000)
        m.receive(perfData)
        #expect(ms { for v in sidebarViews(m) { _ = m.count(of: v) } } < 300)
        #expect(ms { _ = SearchModel(query: "zhoubao", data: m.searchData) } < 1500)
    }
}

@Suite("performance", .serialized, .enabled(if: measuring, "OT_PERF=1 to measure"))
struct PerformanceTests {
    @Test("the fixture is the size asked for")
    func fixture() {
        #expect(perfData.tasks.count == 5000)
        #expect(perfData.tasks.count { $0.status != .open } == 3500)
        #expect(perfData.checklistItems.count == 8000)
        #expect(perfData.lists.count == 20)
        #expect(perfData.tasks.count { $0.listId == perfBigList } > 1000)
    }

    // MARK: Database

    @Test("opening the database to the first snapshot, and a change to the next")
    func database() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "perf-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try AppDatabase.open(at: url)
        try await insertPerfData(perfData, into: db)

        let open = try await perfTimeAsync("open + first TaskData", runs: 3) {
            let fresh = try AppDatabase.open(at: url)
            let data = try await fresh.observeTaskData().first()
            #expect(data.tasks.count == 5000)
        }
        #expect(open < 3000)

        let repo = TaskRepo(db, clock: { perfNow.date(in: perfZone) }, timeZone: perfZone)
        let model = AppModel(repo: repo, settings: LocalSettings(db), now: perfNow)
        await model.start(clock: false)
        var tries = 0
        while !model.loaded && tries < 400 { tries += 1; try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.loaded)
        var p = Priority.none
        let change = try await perfTimeAsync("write one task → new snapshot in the model", runs: 5) {
            p = p == .high ? .low : .high
            try await repo.setPriority("t4000", p)
            var waited = 0
            while model.task("t4000")?.priority != p && waited < 3000 { waited += 1; try await Task.sleep(for: .milliseconds(1)) }
            #expect(model.task("t4000")?.priority == p)
        }
        #expect(change < 3000)

        // The sync engine's scan for rows to push, and the scheduler's count.
        perfTime("sync: dirty rows (one page)") { _ = try! db.writer.read { try dirtyRecords($0, limit: 500) } }
        perfTime("sync: dirty count") { _ = try! db.writer.read { try dirtyCount($0) } }
    }

    // MARK: Views

    @Test("smart lists, a big list in every grouping and order, 已完成")
    func views() throws {
        let m = try makeModel()
        var limit = 0.0
        limit = max(limit, perfTime("sections: 今天") { m.receive(perfData); _ = m.sections(for: .smart(.today)) })
        limit = max(limit, perfTime("sections: 最近7天") { m.receive(perfData); _ = m.sections(for: .smart(.next7)) })
        limit = max(limit, perfTime("sections: 收集箱") { m.receive(perfData); _ = m.sections(for: .smart(.inbox)) })
        limit = max(limit, perfTime("sections: 已完成") { m.receive(perfData); _ = m.sections(for: .smart(.completed)) })
        limit = max(limit, perfTime("sections: 垃圾桶") { m.receive(perfData); _ = m.sections(for: .smart(.trash)) })
        let big = ViewRef.list(perfBigList)
        for g in groupingsFor(big) {
            m.settings.setGrouping(big, g)
            for s in sortsFor(big) {
                m.settings.setSort(big, s)
                limit = max(limit, perfTime("sections: 大清单 \(g.rawValue)/\(s.rawValue)", runs: 1) { m.receive(perfData); _ = m.sections(for: big) })
            }
        }
        #expect(limit < 400)

        // What the body asks for each row on top of the sections.
        // After a change: the sections, then every row's lookups.
        let rows = perfTime("rows: 大清单 (after a change)") { m.receive(perfData); _ = rowWork(m, big) }
        let done = perfTime("rows: 已完成 (after a change)") { m.receive(perfData); _ = rowWork(m, .smart(.completed)) }
        // The same body again with nothing changed (another frame).
        perfTime("rows: 大清单 (again)") { _ = rowWork(m, big) }
        #expect(rows < 500 && done < 1000)
    }

    @Test("the sidebar's counts, tags and lookups")
    func sidebar() throws {
        let m = try makeModel()
        let views = sidebarViews(m)
        let counts = perfTime("sidebar: \(views.count) counts (after a change)") { m.receive(perfData); for v in views { _ = m.count(of: v) } }
        // The same numbers as counting each view on its own.
        for v in views { #expect(m.count(of: v) == openCount(v, m.data.tasks, m.now, m.filterRules), "\(v)") }
        perfTime("sidebar: \(views.count) counts, each view on its own (before)") {
            for v in views { _ = openCount(v, m.data.tasks, m.now, m.filterRules) }
        }
        let tags = perfTime("sidebar: tags (after a change)") { m.receive(perfData); _ = m.tags }
        let lookups = perfTime("lookups: listsById ×100") { for _ in 0..<100 { _ = m.listsById } }
        let find = perfTime("lookups: task(id) ×100 (after a change)") { m.receive(perfData); for i in 0..<100 { _ = m.task("t\(i * 49)") } }
        #expect(counts < 300 && tags < 200 && lookups < 200 && find < 200)
    }

    @Test("search, filters, calendar, timeline, board, reminders")
    func features() throws {
        let m = try makeModel()
        let data = perfTime("search: data (after a change)") { m.receive(perfData); _ = m.searchData }
        let sd = m.searchData
        let zh = perfTime("search: 周报") { _ = SearchModel(query: "周报", data: sd) }
        let py = perfTime("search: zhoubao") { _ = SearchModel(query: "zhoubao", data: sd) }
        let initials = perfTime("search: zb") { _ = SearchModel(query: "zb", data: sd) }
        #expect(data < 300 && zh < 1000 && py < 3000 && initials < 3000)
        // The letter prefilter behind these never changes what's found.
        for t in perfData.tasks.prefix(1000) {
            for term in ["zhoubao", "zb", "zl", "bg", "xzb", "huiyi", "lvxing"] {
                #expect(pinyinRanges(t.title, term, prefilter: true) == pinyinRanges(t.title, term, prefilter: false))
            }
        }
        // The panel's body again with the same text and data (a cursor
        // move, a redraw): no new search.
        let memo = SearchMemo()
        _ = memo.model(query: "zhoubao", data: m.searchData, recent: RecentSearches())
        let again = perfTime("search: zhoubao, drawn again") {
            _ = memo.model(query: "zhoubao", data: m.searchData, recent: RecentSearches())
        }
        #expect(again < 50)

        let filters = perfTime("filters: all five, sections (after a change)") { m.receive(perfData); for f in m.filters { _ = m.sections(for: .filter(f.id)) } }
        #expect(filters < 1000)

        let month = monthGrid(perfToday.year, perfToday.month)
        let cal = perfTime("calendar: month entries") {
            _ = calendarEntries(m.data.tasks, month, today: perfToday, filter: CalendarFilter())
        }
        #expect(cal < 1000)

        let tl = perfTime("timeline: 大清单") { _ = m.timeline(for: .list(perfBigList)) }
        let tlToday = perfTime("timeline: 今天") { _ = m.timeline(for: .smart(.today)) }
        let board = perfTime("board: 大清单") { _ = m.boardColumns(.list(perfBigList)) }
        #expect(tl < 500 && tlToday < 500 && board < 500)

        let rem = perfTime("reminders: upcoming") { _ = upcomingReminders(m.data.tasks, perfNow) }
        #expect(rem < 300)
    }
}
