// Ported from `app/test/pinyin_test.dart`.

import Testing
@testable import OpenTodoDomain

@Suite("pinyin")
struct PinyinTests {
    @Test("reads characters from the table and the polyphone list")
    func readings() {
        func c(_ s: String) -> Int { Int(s.unicodeScalars.first!.value) }
        #expect(pinyinReadings(c("周")) == ["zhou"])
        #expect(pinyinReadings(c("报")) == ["bao"])
        #expect(pinyinReadings(c("女")) == ["nv"])
        #expect(pinyinReadings(c("长")) == ["chang", "zhang"])
        #expect(pinyinReadings(c("〇")) == ["ling"])
        #expect(pinyinReadings(c("a")).isEmpty)
        #expect(pinyinReadings(c("，")).isEmpty)
        #expect(hasHan("写周报"))
        #expect(!hasHan("report 1"))
    }

    @Test("sorts Chinese and Latin titles together, A to Z")
    func sorting() {
        let titles = ["周报", "apple", "爱好", "Banana", "吃饭", "123", "ah", "aj", "长期目标"]
        #expect(titles.sorted(comparing: comparePinyin)
            == ["123", "ah", "爱好", "aj", "apple", "Banana", "长期目标", "吃饭", "周报"])
    }

    @Test("finds a title by its pinyin, initials or a mix")
    func ranges() {
        #expect(pinyinRanges("写周报", "zhoubao") == [1..<3])
        #expect(pinyinRanges("写周报", "zb") == [1..<3])
        #expect(pinyinRanges("写周报", "zhoub") == [1..<3])
        #expect(pinyinRanges("写周报", "xzb") == [0..<3])
        #expect(pinyinRanges("写周报", "zhb") == [1..<3])
        #expect(pinyinRanges("写周报", "bz").isEmpty)
        #expect(pinyinRanges("去银行", "yinhang") == [1..<3])
        #expect(pinyinRanges("去银行", "yh") == [1..<3])
        #expect(pinyinRanges("买绿茶", "lvcha") == [1..<3])
        #expect(pinyinRanges("买绿茶", "lucha") == [1..<3])
        // Latin in the title matches as itself; spaces can be skipped.
        #expect(pinyinRanges("看 PPT 讲稿", "pptjg") == [2..<8])
        #expect(pinyinRanges("周会 周报", "zh") == [0..<1, 3..<4])
        #expect(pinyinRanges("写周报", "zhou bao").isEmpty)
        #expect(pinyinRanges("写周报", "").isEmpty)
    }

    // Not in the Dart test: ruling texts out by their letters never
    // changes what's found.
    @Test("the letter prefilter never changes an answer")
    func prefilter() {
        let texts = ["写周报", "去银行", "买绿茶", "看 PPT 讲稿", "周会 周报", "女儿的绿色毛衣", "Kelvin 温度", "\u{212A}一", "İstanbul 行程",
                     "整理文档 12", "长期目标", "〇号", "，。！", "😀周报", "ABC 周一 Zoom 会议", "旅游攻略", "略"]
        let terms = ["zhoubao", "zb", "zhb", "yinhang", "yh", "lvcha", "lucha", "pptjg", "zh", "nver", "lvse", "nu", "lu",
                     "k", "kelvin", "istanbul", "zl", "zhengli", "changqi", "zhang", "ling", "lh", "zoom", "lve", "lue", "x", "abc"]
        for text in texts {
            for term in terms {
                #expect(pinyinRanges(text, term, prefilter: true) == pinyinRanges(text, term, prefilter: false), "\(text) \(term)")
            }
        }
    }

    // Not in the Dart test: the converted table, end to end.
    @Test("the whole table converted")
    func table() {
        #expect(pinyinReadings(0x4E00) == ["yi"]) // 一, the first entry
        #expect(pinyinReadings(0x9F99) == ["long"]) // 龙
        #expect(pinyinReadings(0x4DFF).isEmpty)
        #expect(pinyinSortKey("周报 Q3") == "zhoubao q3")
        // Ranges are UTF-16: an emoji before counts two.
        #expect(pinyinRanges("😀周报", "zb") == [2..<4])
    }
}
