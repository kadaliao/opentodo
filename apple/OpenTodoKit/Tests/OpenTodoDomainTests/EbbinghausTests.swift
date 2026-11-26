// 艾宾浩斯记忆法 repeats: a Swift-version addition with no Dart test to
// port (see `ebbinghausReviewDays` in Recurrence.swift).

import Testing
@testable import OpenTodoDomain

// A Sunday.
private let study = Day(2026, 11, 15)

/// The rule an older app (the Dart version) reads: it ignores parts it
/// doesn't know, which here is just X-EBBINGHAUS.
private func asOlderAppReads(_ text: String) -> RepeatRule? {
    RepeatRule.tryParse(text.split(separator: ";").filter { !$0.hasPrefix("X-EBBINGHAUS=") }.joined(separator: ";"))
}

@Suite("艾宾浩斯记忆法")
struct EbbinghausTests {
    @Test("text, round by round") func text() {
        #expect(RepeatRule.ebbinghaus.description == "FREQ=DAILY;X-EBBINGHAUS=0;COUNT=9")
        #expect(RepeatRule.ebbinghaus(round: 2).description == "FREQ=DAILY;INTERVAL=2;X-EBBINGHAUS=2;COUNT=7")
        #expect(RepeatRule.ebbinghaus(round: 8).description == "FREQ=DAILY;X-EBBINGHAUS=8;COUNT=1")
        for k in 0...ebbinghausReviewDays.count {
            let r = RepeatRule.ebbinghaus(round: k)
            #expect(RepeatRule.tryParse(r.description) == r)
            #expect(RepeatRule.tryParse(r.description)?.ebbinghausRound == k)
        }
        // The round decides; INTERVAL and COUNT follow from it.
        #expect(RepeatRule.tryParse("FREQ=DAILY;INTERVAL=9;X-EBBINGHAUS=3;COUNT=50") == .ebbinghaus(round: 3))
        #expect(RepeatRule.tryParse("x-ebbinghaus=1;freq=daily") == .ebbinghaus(round: 1))
        // Not a round of the series: read as the plain rule.
        #expect(RepeatRule.tryParse("FREQ=DAILY;X-EBBINGHAUS=9;COUNT=3")?.description == "FREQ=DAILY;COUNT=3")
        #expect(RepeatRule.tryParse("FREQ=DAILY;X-EBBINGHAUS=abc")?.ebbinghausRound == nil)
        // Still needs a FREQ, as every rule does.
        #expect(RepeatRule.tryParse("X-EBBINGHAUS=0") == nil)
    }

    @Test("reviews 1, 2, 4, 7, 15, 30, 90 and 180 days after the study, then stops") func schedule() {
        #expect(ebbinghausReviewDays == [1, 2, 4, 7, 15, 30, 90, 180])
        #expect(Array(occurrencesAfter(.ebbinghaus, study)) == ebbinghausReviewDays.map { study + $0 })
        // From the third review (day 4) on.
        #expect(Array(occurrencesAfter(.ebbinghaus(round: 3), study + 4)) == [7, 15, 30, 90, 180].map { study + $0 })
        #expect(Array(occurrencesAfter(.ebbinghaus(round: 8), study + 180)).isEmpty)
        #expect(nextOccurrence(.ebbinghaus, study) == study + 1)
        #expect(nextOccurrence(.ebbinghaus(round: 5), study + 15) == study + 30)
        #expect(nextOccurrence(.ebbinghaus(round: 6), study + 30) == study + 90)
        #expect(nextOccurrence(.ebbinghaus(round: 8), study + 180) == nil)
        #expect(firstOccurrence(.ebbinghaus, study) == study)
    }

    @Test("completing each session on its day walks the series") func completingOnTime() throws {
        var rule = RepeatRule.ebbinghaus
        var due = study
        var dates: [Day] = []
        while let a = advanceRepeat(rule, due, today: due) {
            dates.append(a.date)
            rule = a.rule
            due = a.date
        }
        #expect(dates == ebbinghausReviewDays.map { study + $0 })
        #expect(rule == .ebbinghaus(round: 8))
        #expect(advanceRepeat(rule, due, today: due) == nil) // the last review closes the task
    }

    @Test("a review done late counts from that day; done early, from its date") func lateAndEarly() throws {
        // The third review was due on day 4 (gap to the next: 3 days).
        let late = try #require(advanceRepeat(.ebbinghaus(round: 3), study + 4, today: study + 6))
        #expect(late.date == study + 9)
        #expect(late.rule == .ebbinghaus(round: 4))
        // No round is skipped, whichever way the task counts.
        let fromCompletion = try #require(
            advanceRepeat(.ebbinghaus(round: 3), study + 4, today: study + 20, repeatFrom: .completion)
        )
        #expect(fromCompletion.date == study + 23)
        #expect(fromCompletion.rule == .ebbinghaus(round: 4))
        let early = try #require(advanceRepeat(.ebbinghaus(round: 3), study + 4, today: study + 2))
        #expect(early.date == study + 7)
    }

    @Test("an older app reads a daily rule landing on the next review") func olderApp() throws {
        for k in 0..<ebbinghausReviewDays.count {
            let r = RepeatRule.ebbinghaus(round: k)
            let due = study + (k == 0 ? 0 : ebbinghausReviewDays[k - 1])
            let old = try #require(asOlderAppReads(r.description))
            #expect(old.ebbinghausRound == nil)
            #expect(old.freq == .daily)
            #expect(nextOccurrence(old, due) == nextOccurrence(r, due), "round \(k)")
            #expect(old.count == r.count)
        }
        // At the last review it ends there too.
        let last = try #require(asOlderAppReads(RepeatRule.ebbinghaus(round: 8).description))
        #expect(nextOccurrence(last, study + 180) == nil)
    }

    @Test("described in words") func words() {
        #expect(describeRepeat(.ebbinghaus, study) == "艾宾浩斯记忆法，复习8次")
        #expect(describeRepeat(.ebbinghaus(round: 3), study, repeatFrom: .completion) == "艾宾浩斯记忆法，第3次复习（共8次）")
        #expect(describeRepeat(.ebbinghaus(round: 8), study) == "艾宾浩斯记忆法，第8次复习（共8次）")
    }

    @Test("quick add: 艾宾浩斯 and 记忆曲线") func quickAdd() throws {
        let now = LocalDateTime(2026, 11, 15, 10)
        let text = RepeatRule.ebbinghaus.description

        var r = parseQuickAdd("艾宾浩斯 背单词", now: now)
        #expect(r.repeat == .ebbinghaus)
        #expect(r.title == "背单词")
        #expect(r.date == study)

        r = parseQuickAdd("按记忆曲线复习第三章 #英语", now: now)
        #expect(r.repeat?.description == text)
        #expect(r.title == "复习第三章")
        #expect(r.tags == ["英语"])

        r = parseQuickAdd("明天遗忘曲线背课文", now: now)
        #expect(r.repeat == .ebbinghaus)
        #expect(r.title == "背课文")
        #expect(r.date == study + 1)

        r = parseQuickAdd("按艾宾浩斯记忆法 晚上8点 背古诗", now: now)
        #expect(r.repeat == .ebbinghaus)
        #expect(r.title == "背古诗")
        #expect(r.date == study)
        #expect(r.time == 20 * 60)
        #expect(r.tokens.first == QuickAddToken(0, 8, .repeat))

        // 8:00 has gone by: the study is tomorrow, as for any repeat.
        #expect(parseQuickAdd("艾宾浩斯记忆曲线 8点背单词", now: now).date == study + 1)
        // Plain words stay words.
        #expect(parseQuickAdd("复习艾宾", now: now).repeat == nil)
    }
}
