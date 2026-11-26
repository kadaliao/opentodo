// Ported from app/test/quick_add_parser_test.dart, case for case.

import Foundation
import Testing
@testable import OpenTodoDomain

// Sunday, 15 November 2026, 10:00.
private let quickAddNow = LocalDateTime(2026, 11, 15, 10)

private func hm(_ m: Int) -> String {
    let h = m / 60 % 24, mm = m % 60
    return (h < 10 ? "0" : "") + "\(h):" + (mm < 10 ? "0" : "") + "\(mm)"
}

private func expectParse(
    _ input: String,
    title: String,
    date: String? = nil,
    time: String? = nil,
    tags: [String] = [],
    priority: Priority? = nil,
    repeat: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let r = parseQuickAdd(input, now: quickAddNow)
    #expect(r.repeat?.description == `repeat`, "repeat of \"\(input)\"", sourceLocation: sourceLocation)
    #expect(r.title == title, "title of \"\(input)\"", sourceLocation: sourceLocation)
    #expect(r.date?.key == date, "date of \"\(input)\"", sourceLocation: sourceLocation)
    #expect(r.time.map(hm) == time, "time of \"\(input)\"", sourceLocation: sourceLocation)
    #expect(r.tags == tags, "tags of \"\(input)\"", sourceLocation: sourceLocation)
    #expect(r.priority == priority, "priority of \"\(input)\"", sourceLocation: sourceLocation)
}

/// `15:00-17:00 开会` for a span, `15:00` for a lone time, nil for none.
private func span(_ input: String) -> String? {
    let r = parseQuickAdd(input, now: quickAddNow)
    guard let time = r.time else { return nil }
    guard let duration = r.duration else { return hm(time) }
    return "\(hm(time))-\(hm(time + duration)) \(r.title)"
}

@Suite("quick add parser")
struct QuickAddParserTests {
    @Test("plain text has no date") func plainText() {
        expectParse("买牛奶", title: "买牛奶")
        expectParse("  ", title: "")
    }

    // MARK: relative days

    @Test("relative days: 今天 明天 后天 大后天") func relativeDays() {
        expectParse("今天交报告", title: "交报告", date: "2026-11-15")
        expectParse("明天交报告", title: "交报告", date: "2026-11-16")
        expectParse("后天交报告", title: "交报告", date: "2026-11-17")
        expectParse("大后天交报告", title: "交报告", date: "2026-11-18")
    }

    @Test("relative days: 今晚 and 明早 carry a default time") func defaultTimes() {
        expectParse("今晚 看电影", title: "看电影", date: "2026-11-15", time: "20:00")
        expectParse("明早 跑步", title: "跑步", date: "2026-11-16", time: "08:00")
        expectParse("今晚8点 看电影", title: "看电影", date: "2026-11-15", time: "20:00")
    }

    @Test("relative days: N天后") func daysLater() {
        expectParse("3天后 复查", title: "复查", date: "2026-11-18")
        expectParse("两周后复查", title: "复查", date: "2026-11-29")
    }

    // MARK: weekdays (today is Sunday)

    @Test("weekdays: 周X is the next one, today included") func weekdayNext() {
        expectParse("周三交周报", title: "交周报", date: "2026-11-18")
        expectParse("星期天 休息", title: "休息", date: "2026-11-15")
        expectParse("礼拜五聚餐", title: "聚餐", date: "2026-11-20")
    }

    @Test("weekdays: 下周X and 这周X use Monday-start weeks") func weekdayWeeks() {
        expectParse("下周一 项目评审", title: "项目评审", date: "2026-11-16")
        expectParse("下下周二 复盘", title: "复盘", date: "2026-11-24")
        expectParse("这周三 已经过了", title: "已经过了", date: "2026-11-11")
    }

    @Test("weekdays: 下周 alone is next Monday; 周末 is Saturday or today") func weekAndWeekend() {
        expectParse("下周 开会", title: "开会", date: "2026-11-16")
        expectParse("周末 大扫除", title: "大扫除", date: "2026-11-15")
        expectParse("下周末 爬山", title: "爬山", date: "2026-11-21")
    }

    // MARK: calendar dates

    @Test("calendar dates: month and day") func monthAndDay() {
        expectParse("11月20日交房租", title: "交房租", date: "2026-11-20")
        expectParse("十二月一号 体检", title: "体检", date: "2026-12-01")
        expectParse("1月3日 回家", title: "回家", date: "2027-01-03")
        expectParse("12/25 圣诞", title: "圣诞", date: "2026-12-25")
        expectParse("2027年2月1日 续签", title: "续签", date: "2027-02-01")
    }

    @Test("calendar dates: day of month") func dayOfMonth() {
        expectParse("20号 还信用卡", title: "还信用卡", date: "2026-11-20")
        expectParse("10号 交水费", title: "交水费", date: "2026-12-10")
    }

    @Test("calendar dates: a day already past in December is next January") func dayOfMonthInDecember() {
        // Not in the Dart version, which leaves it as text in December.
        let december = LocalDateTime(2026, 12, 20, 10)
        #expect(parseQuickAdd("10号 交水费", now: december).date == Day(2027, 1, 10))
        #expect(parseQuickAdd("25号 交水费", now: december).date == Day(2026, 12, 25))
        // 30号 on 31 December: January has one.
        #expect(parseQuickAdd("30号 对账", now: LocalDateTime(2026, 12, 31, 10)).date == Day(2027, 1, 30))
        // 30号 on 31 January: February hasn't, so March.
        #expect(parseQuickAdd("30号 对账", now: LocalDateTime(2027, 1, 31, 10)).date == Day(2027, 3, 30))
    }

    @Test("calendar dates: impossible dates are left as text") func impossibleDates() {
        expectParse("2月30日", title: "2月30日")
    }

    // MARK: times

    @Test("times: with a period") func timesWithPeriod() {
        expectParse("明天下午3点开会", title: "开会", date: "2026-11-16", time: "15:00")
        expectParse("晨会 今天上午9点", title: "晨会", date: "2026-11-15", time: "09:00")
        expectParse("中午12点半 吃饭", title: "吃饭", date: "2026-11-15", time: "12:30")
        expectParse("晚上十点 睡觉", title: "睡觉", date: "2026-11-15", time: "22:00")
        expectParse("下午3点15分 电话", title: "电话", date: "2026-11-15", time: "15:15")
        expectParse("凌晨1点 收衣服", title: "收衣服", date: "2026-11-15", time: "01:00")
    }

    @Test("times: without a period, 1-6 means the afternoon") func timesWithoutPeriod() {
        expectParse("3点开会", title: "开会", date: "2026-11-15", time: "15:00")
        expectParse("9:00 晨会", title: "晨会", date: "2026-11-15", time: "09:00")
        expectParse("8点一刻 出门", title: "出门", date: "2026-11-15", time: "08:15")
    }

    @Test("times: am and pm") func amPm() {
        expectParse("meeting 3pm", title: "meeting", date: "2026-11-15", time: "15:00")
        expectParse("call 9:30am", title: "call", date: "2026-11-15", time: "09:30")
    }

    @Test("times: 一点点 is not a time") func notATime() {
        expectParse("吃一点点东西", title: "吃一点点东西")
    }

    // MARK: tags and priority

    @Test("tags are removed from the title") func tags() {
        expectParse("买机票 #出行", title: "买机票", tags: ["出行"])
        expectParse("#读书 读完一本书 #自我提升", title: "读完一本书", tags: ["读书", "自我提升"])
    }

    @Test("# inside a word is not a tag") func hashInWord() {
        expectParse("买C#的书", title: "买C#的书")
    }

    @Test("priority") func priority() {
        expectParse("交税 !高", title: "交税", priority: .high)
        expectParse("交税 ！中", title: "交税", priority: .medium)
        expectParse("交税 !1", title: "交税", priority: .low)
        expectParse("加油!", title: "加油!")
    }

    @Test("everything together") func everything() {
        expectParse("明天下午3点开会 #工作 !高", title: "开会", date: "2026-11-16", time: "15:00", tags: ["工作"], priority: .high)
    }

    // MARK: tokens

    @Test("tokens mark the recognised text") func tokens() {
        let input = "明天下午3点开会 #工作"
        let r = parseQuickAdd(input, now: quickAddNow)
        #expect(r.tokens == [
            QuickAddToken(0, 2, .date),
            QuickAddToken(2, 6, .time),
            QuickAddToken(9, 12, .tag),
        ])
        // The same spans as string indices and as NSRanges.
        #expect(r.tokens.map { String(input[$0.range(in: input)]) } == ["明天", "下午3点", "#工作"])
        #expect(r.tokens.map { (input as NSString).substring(with: $0.nsRange) } == ["明天", "下午3点", "#工作"])
    }

    @Test("tokens are UTF-16 offsets, past characters outside the BMP") func tokensUTF16() {
        let input = "🎉明天聚会 #派对"
        let r = parseQuickAdd(input, now: quickAddNow)
        #expect(r.title == "🎉 聚会")
        #expect(r.tokens == [QuickAddToken(2, 4, .date), QuickAddToken(7, 10, .tag)])
        #expect(r.tokens.map { String(input[$0.range(in: input)]) } == ["明天", "#派对"])
    }

    @Test("parseNumber") func numbers() {
        #expect(parseNumber("3") == 3)
        #expect(parseNumber("十") == 10)
        #expect(parseNumber("十一") == 11)
        #expect(parseNumber("二十") == 20)
        #expect(parseNumber("三十一") == 31)
        #expect(parseNumber("两") == 2)
        #expect(parseNumber("abc") == nil)
    }

    // MARK: repeat

    @Test("repeat: daily, with the time of day") func repeatDaily() {
        expectParse("每天吃药", title: "吃药", date: "2026-11-15", repeat: "FREQ=DAILY")
        // 8:00 has passed today, so it starts tomorrow.
        expectParse("每天早上8点吃药", title: "吃药", date: "2026-11-16", time: "08:00", repeat: "FREQ=DAILY")
        expectParse("每天晚上9点吃药", title: "吃药", date: "2026-11-15", time: "21:00", repeat: "FREQ=DAILY")
        expectParse("每3天浇花", title: "浇花", date: "2026-11-15", repeat: "FREQ=DAILY;INTERVAL=3")
    }

    @Test("repeat: weekly on given days starts on the first of them") func repeatWeekly() {
        expectParse("每周一例会", title: "例会", date: "2026-11-16", repeat: "FREQ=WEEKLY;BYDAY=MO")
        expectParse("每周一三五跑步", title: "跑步", date: "2026-11-16", repeat: "FREQ=WEEKLY;BYDAY=MO,WE,FR")
        expectParse("每周二、四下午3点 网球", title: "网球", date: "2026-11-17", time: "15:00", repeat: "FREQ=WEEKLY;BYDAY=TU,TH")
        expectParse("每个星期天大扫除", title: "大扫除", date: "2026-11-15", repeat: "FREQ=WEEKLY;BYDAY=SU")
        expectParse("每周写周报", title: "写周报", date: "2026-11-15", repeat: "FREQ=WEEKLY")
        expectParse("每两周 理发", title: "理发", date: "2026-11-15", repeat: "FREQ=WEEKLY;INTERVAL=2")
    }

    @Test("repeat: workdays and weekends") func repeatWorkdays() {
        expectParse("每个工作日打卡", title: "打卡", date: "2026-11-16", repeat: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
        expectParse("每周末爬山", title: "爬山", date: "2026-11-15", repeat: "FREQ=WEEKLY;BYDAY=SA,SU")
        // Without 每 it's just words.
        expectParse("整理工作日志", title: "整理工作日志")
    }

    @Test("repeat: monthly and yearly") func repeatMonthlyYearly() {
        expectParse("每月15号还信用卡", title: "还信用卡", date: "2026-11-15", repeat: "FREQ=MONTHLY;BYMONTHDAY=15")
        expectParse("每月1号交房租", title: "交房租", date: "2026-12-01", repeat: "FREQ=MONTHLY;BYMONTHDAY=1")
        expectParse("每月最后一天对账", title: "对账", date: "2026-11-30", repeat: "FREQ=MONTHLY;BYMONTHDAY=-1")
        expectParse("每个月体检", title: "体检", date: "2026-11-15", repeat: "FREQ=MONTHLY")
        expectParse("每3个月换滤芯", title: "换滤芯", date: "2026-11-15", repeat: "FREQ=MONTHLY;INTERVAL=3")
        expectParse("每年3月8日送花", title: "送花", date: "2027-03-08", repeat: "FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=8")
        expectParse("每年体检", title: "体检", date: "2026-11-15", repeat: "FREQ=YEARLY")
    }

    @Test("repeat: an explicit date sets where it starts") func repeatExplicitDate() {
        expectParse("下周三每天跑步", title: "跑步", date: "2026-11-18", repeat: "FREQ=DAILY")
        expectParse("明天 每周写周报 #工作", title: "写周报", date: "2026-11-16", tags: ["工作"], repeat: "FREQ=WEEKLY")
    }

    @Test("repeat: highlighted as a token") func repeatToken() {
        let r = parseQuickAdd("每周一例会", now: quickAddNow)
        #expect(r.tokens == [QuickAddToken(0, 3, .repeat)])
    }

    // MARK: spans

    @Test("spans: X点到Y点, with or without 上午/下午") func spans() {
        #expect(span("明天下午3点到5点开会") == "15:00-17:00 开会")
        #expect(span("3点到5点开会") == "15:00-17:00 开会")
        #expect(span("上午9点到11点半 写方案") == "09:00-11:30 写方案")
        // The end comes after the start: 上午11点到1点 ends at 13:00.
        #expect(span("上午11点到1点 午餐会") == "11:00-13:00 午餐会")
        #expect(span("上午10点到下午2点 培训") == "10:00-14:00 培训")
    }

    @Test("spans: clock times and am/pm") func spanClock() {
        #expect(span("15:00-16:30 评审") == "15:00-16:30 评审")
        #expect(span("9:00~10:00 站会") == "09:00-10:00 站会")
        #expect(span("3pm-5pm 健身") == "15:00-17:00 健身")
    }

    @Test("spans: past midnight") func spanPastMidnight() {
        let r = parseQuickAdd("晚上10点到凌晨2点 值班", now: quickAddNow)
        #expect(r.time == 22 * 60)
        #expect(r.duration == 240)
        #expect(r.title == "值班")
    }

    @Test("spans: the whole span is one highlighted token") func spanToken() throws {
        let input = "开会 下午3点到5点"
        let r = parseQuickAdd(input, now: quickAddNow)
        let token = try #require(r.tokens.first)
        #expect(r.tokens.count == 1)
        #expect(token.kind == .time)
        #expect(String(input[token.range(in: input)]) == "下午3点到5点")
    }

    @Test("spans: a lone time or a dash elsewhere is no span") func noSpan() {
        #expect(parseQuickAdd("下午3点开会", now: quickAddNow).duration == nil)
        #expect(span("3点 A-B 测试") == "15:00")
    }

    // MARK: China

    @Test("China: 法定工作日") func statutoryWorkdays() {
        expectParse(
            "每个法定工作日9点打卡", title: "打卡",
            date: "2026-11-16", // today (Sunday) isn't one
            time: "09:00", repeat: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;X-HOLIDAYS=CN"
        )
        expectParse("每个工作日站会", title: "站会", date: "2026-11-16", repeat: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
    }

    @Test("China: lunar repeats") func lunarRepeats() {
        expectParse(
            "每年农历八月十五 买月饼", title: "买月饼",
            date: "2027-09-15", // 2026's was in September
            repeat: "RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=8;BYMONTHDAY=15;SKIP=BACKWARD"
        )
        expectParse(
            "农历每年腊月初八喝粥", title: "喝粥", date: "2027-01-15",
            repeat: "RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=8;SKIP=BACKWARD"
        )
        expectParse(
            "农历每月初一上香", title: "上香", date: "2026-12-09",
            repeat: "RSCALE=CHINESE;FREQ=MONTHLY;BYMONTHDAY=1;SKIP=BACKWARD"
        )
        expectParse(
            "每年除夕年夜饭", title: "年夜饭", date: "2027-02-05",
            repeat: "RSCALE=CHINESE;FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=30;SKIP=BACKWARD"
        )
    }

    @Test("China: a lunar date once") func lunarOnce() {
        expectParse("农历八月十五回家", title: "回家", date: "2027-09-15")
        expectParse("农历十月初九 生日", title: "生日", date: "2026-11-17")
        expectParse("除夕前大扫除", title: "前大扫除", date: "2027-02-05")
        // Without 农历 it is still August.
        expectParse("八月十五交房租", title: "交房租", date: "2027-08-15")
    }
}
