// Pinyin for Chinese text, ported from `app/lib/domain/pinyin.dart`: sorting
// titles in pinyin order, and finding 周报 by typing `zhoubao`, `zb` or
// `zhoub`.
//
// Each character has one reading from the table (`PinyinTable.swift`), plus
// the other common readings of the polyphones listed in `polyphones`, so
// `yinhang` finds 银行. Readings are toneless, ü written v (a `u` typed
// matches it too).
//
// Positions are UTF-16 offsets, as in Dart (and `NSRange`): a range from
// `pinyinRanges` indexes `text.utf16`. Comparisons of plain text are by
// UTF-16 code units too, like Dart's `String.compareTo` (`compareUTF16`).

import Synchronization

/// Every reading of common polyphones (多音字); the first is the one used
/// for sorting, where it differs from the table's.
private let polyphones: [(Character, [String])] = [
    ("长", ["chang", "zhang"]),
    ("地", ["di", "de"]),
    ("茄", ["qie", "jia"]),
    ("行", ["xing", "hang"]),
    ("重", ["zhong", "chong"]),
    ("还", ["hai", "huan"]),
    ("都", ["dou", "du"]),
    ("的", ["de", "di"]),
    ("得", ["de", "dei"]),
    ("了", ["le", "liao"]),
    ("乐", ["le", "yue"]),
    ("觉", ["jue", "jiao"]),
    ("会", ["hui", "kuai"]),
    ("朝", ["chao", "zhao"]),
    ("调", ["diao", "tiao"]),
    ("数", ["shu", "shuo"]),
    ("着", ["zhe", "zhao", "zhuo"]),
    ("便", ["bian", "pian"]),
    ("藏", ["cang", "zang"]),
    ("传", ["chuan", "zhuan"]),
    ("弹", ["dan", "tan"]),
    ("差", ["cha", "chai", "ci"]),
    ("和", ["he", "huo", "hu"]),
    ("降", ["jiang", "xiang"]),
    ("角", ["jiao", "jue"]),
    ("卡", ["ka", "qia"]),
    ("落", ["luo", "la", "lao"]),
    ("没", ["mei", "mo"]),
    ("省", ["sheng", "xing"]),
    ("校", ["xiao", "jiao"]),
    ("薄", ["bao", "bo"]),
    ("称", ["cheng", "chen"]),
    ("系", ["xi", "ji"]),
    ("血", ["xue", "xie"]),
    ("盛", ["sheng", "cheng"]),
    ("参", ["can", "shen", "cen"]),
    ("单", ["dan", "shan", "chan"]),
    ("仇", ["chou", "qiu"]),
    ("大", ["da", "dai"]),
    ("给", ["gei", "ji"]),
    ("似", ["si", "shi"]),
    ("区", ["qu", "ou"]),
    ("期", ["qi", "ji"]),
    ("露", ["lu", "lou"]),
    ("解", ["jie", "xie"]),
    ("车", ["che", "ju"]),
    ("哪", ["na", "nei"]),
    ("那", ["na", "nei"]),
    ("壳", ["ke", "qiao"]),
    ("剥", ["bo", "bao"]),
    ("识", ["shi", "zhi"]),
    ("熟", ["shu", "shou"]),
    ("色", ["se", "shai"]),
    ("塞", ["sai", "se"]),
    ("恶", ["e", "wu"]),
    ("厦", ["sha", "xia"]),
    ("率", ["lv", "shuai"]),
    ("囤", ["dun", "tun"]),
    ("胖", ["pang", "pan"]),
    ("劲", ["jin", "jing"]),
    ("番", ["fan", "pan"]),
    ("粘", ["zhan", "nian"]),
    ("扎", ["zha", "za"]),
    ("咖", ["ka", "ga"]),
    ("尾", ["wei", "yi"]),
    ("秘", ["mi", "bi"]),
    ("泊", ["po", "bo"]),
    ("模", ["mo", "mu"]),
    ("曾", ["ceng", "zeng"]),
    ("仔", ["zi", "zai"]),
    ("奇", ["qi", "ji"]),
    ("抹", ["mo", "ma"]),
    ("宿", ["su", "xiu"]),
    ("亲", ["qin", "qing"]),
    ("圈", ["quan", "juan"]),
    ("绿", ["lv", "lu"]),
    ("六", ["liu", "lu"]),
]

/// The table, parsed once.
private struct PinyinData: Sendable {
    let byCodePoint: [Int: [String]]
    /// One reading per code point from `pinyinFirst`, each a one-element
    /// array (shared, so lookups don't allocate); empty for none.
    let readings: [[String]]
    /// The letters of every reading (`lettersMask`), alongside.
    let lettersByCodePoint: [Int: UInt32]
    let letters: [UInt32]

    init() {
        var known: [Int: [String]] = [:]
        for (c, r) in polyphones { known[Int(c.unicodeScalars.first!.value)] = r }
        byCodePoint = known
        lettersByCodePoint = known.mapValues(lettersMask)

        let syllables = pinyinSyllablesText.split(separator: " ", omittingEmptySubsequences: false).map { [String($0)] }
        var digit = [Int](repeating: -1, count: 128)
        for (i, u) in pinyinAlphabet.utf8.enumerated() { digit[Int(u)] = i }
        let base = pinyinAlphabet.utf8.count
        let codes = Array(pinyinCodesText.utf8)
        var out: [[String]] = []
        out.reserveCapacity(codes.count / 2)
        var i = 0
        while i + 1 < codes.count {
            // Like Dart's `indexOf`, a character outside the alphabet is -1.
            let n = digit[Int(codes[i])] * base + digit[Int(codes[i + 1])]
            out.append(n <= 0 || n >= syllables.count ? [] : syllables[n])
            i += 2
        }
        readings = out
        letters = out.map(lettersMask)
    }
}

/// The letters `readings` are spelled with, a bit each (a = bit 0); `u`
/// along with `v`, as a typed `u` stands for ü.
private func lettersMask(_ readings: [String]) -> UInt32 {
    var m: UInt32 = 0
    for r in readings {
        for u in r.utf8 where (0x61...0x7A).contains(u) {
            m |= 1 << UInt32(u - 0x61)
            if u == 0x76 { m |= 1 << (0x75 - 0x61) }
        }
    }
    return m
}

/// The letters typing the character `codeUnit` in pinyin can use; 0 for
/// anything that isn't a Chinese character.
private func pinyinLetters(_ codeUnit: Int) -> UInt32 {
    if let known = pinyinData.lettersByCodePoint[codeUnit] { return known }
    let i = codeUnit - pinyinFirst
    guard i >= 0, i < pinyinData.letters.count else {
        return codeUnit == 0x3007 ? lettersMask(["ling"]) : 0
    }
    return pinyinData.letters[i]
}

/// Whether `text` has every letter of `term` (lower-case ASCII code
/// units) somewhere: as itself, ignoring case, or in a reading of one of
/// its Chinese characters. Without them `pinyinRanges` can't find `term`,
/// so most texts are ruled out without trying.
private func hasLetters(_ text: String, of term: [UInt16]) -> Bool {
    var need: UInt32 = 0
    for u in term { need |= 1 << UInt32(u - 0x61) }
    var have: UInt32 = 0
    for u in text.utf16 {
        switch u {
        case 0x61...0x7A: have |= 1 << UInt32(u - 0x61)
        case 0x41...0x5A: have |= 1 << UInt32(u - 0x41)
        // KELVIN SIGN lower-cases to k; İ to i and a dot.
        case 0x212A: have |= 1 << (0x6B - 0x61)
        case 0x0130: have |= 1 << (0x69 - 0x61)
        case 0..<0x80: break
        default: have |= pinyinLetters(Int(u))
        }
        if have & need == need { return true }
    }
    return false
}

private let pinyinData = PinyinData()

/// The readings of the character `codePoint`, most common first; empty for
/// anything that isn't a Chinese character.
public func pinyinReadings(_ codePoint: Int) -> [String] {
    if let known = pinyinData.byCodePoint[codePoint] { return known }
    let i = codePoint - pinyinFirst
    guard i >= 0, i < pinyinData.readings.count else {
        return codePoint == 0x3007 ? ["ling"] : [] // 〇
    }
    return pinyinData.readings[i]
}

/// Whether `text` has any Chinese character.
public func hasHan(_ text: String) -> Bool {
    text.unicodeScalars.contains { !pinyinReadings(Int($0.value)).isEmpty }
}

private let sortKeys = Mutex<[String: String]>([:])

/// `text` as it sorts: each Chinese character spelled in pinyin, the rest in
/// lower case. 爱 sorts with `ai`, between `ah` and `aj`.
public func pinyinSortKey(_ text: String) -> String {
    if let cached = sortKeys.withLock({ $0[text] }) { return cached }
    var out = ""
    for r in text.unicodeScalars {
        let p = pinyinReadings(Int(r.value))
        out += p.first ?? String(r).lowercased()
    }
    sortKeys.withLock {
        if $0.count > 4000 { $0.removeAll() }
        $0[text] = out
    }
    return out
}

/// Titles in pinyin order (A–Z, Chinese and Latin together); where two
/// spell the same, by their characters. Negative, zero or positive, like a
/// Dart comparator.
public func comparePinyin(_ a: String, _ b: String) -> Int {
    let c = compareUTF16(pinyinSortKey(a), pinyinSortKey(b))
    return c != 0 ? c : compareUTF16(a, b)
}

/// Where `term` (lower case, letters only) is spelled in `text`: each
/// Chinese character can be typed as its whole pinyin or the start of it
/// (`zb`, `zhoub`, `zhoubao` for 周报); anything else as itself, ignoring
/// case; spaces inside the text can be left out. Returns the UTF-16 ranges,
/// not overlapping, left to right; empty when it isn't there or the term
/// isn't letters.
public func pinyinRanges(_ text: String, _ term: String) -> [Range<Int>] {
    pinyinRanges(text, term, prefilter: true)
}

/// `prefilter`: rule out a text lacking a letter of the term first
/// (`hasLetters`); off only to check that it never changes an answer.
func pinyinRanges(_ text: String, _ term: String, prefilter: Bool) -> [Range<Int>] {
    let term = Array(term.utf16)
    guard !term.isEmpty, term.allSatisfy({ (0x61...0x7A).contains($0) }) else { return [] }
    if prefilter && !hasLetters(text, of: term) { return [] }
    // Code units, so the ranges index the string as highlighting does; a
    // character outside the BMP is never Chinese here and matches nothing.
    let units = Array(text.lowercased().utf16)
    guard units.count == text.utf16.count else { return [] }
    var failed = Set<Int>()

    // The end of a match of term[j...] starting at units[i], or -1.
    func match(_ i: Int, _ j: Int) -> Int {
        if j == term.count { return i }
        if i >= units.count { return -1 }
        let key = i * (term.count + 1) + j
        if failed.contains(key) { return -1 }
        let c = units[i]
        var end = -1
        let readings = pinyinReadings(Int(c))
        if !readings.isEmpty {
            for p in readings {
                let p = Array(p.utf16)
                // The longest typed part of this reading first.
                var k = 0
                while k < p.count && j + k < term.count && same(term[j + k], p[k]) { k += 1 }
                while k >= 1 && end < 0 {
                    end = match(i + 1, j + k)
                    k -= 1
                }
                if end >= 0 { break }
            }
        } else if c == term[j] {
            end = match(i + 1, j + 1)
        } else if j > 0 && (c == 0x20 || c == 0x3000) {
            end = match(i + 1, j)
        }
        if end < 0 { failed.insert(key) }
        return end
    }

    var out: [Range<Int>] = []
    var i = 0
    while i < units.count {
        let end = match(i, 0)
        if end > i {
            out.append(i..<end)
            i = end
        } else {
            i += 1
        }
    }
    return out
}

/// A typed letter against a reading's: `u` also stands for ü (v).
private func same(_ typed: UInt16, _ reading: UInt16) -> Bool {
    typed == reading || (typed == 0x75 && reading == 0x76)
}

// MARK: - Text helpers shared by the domain

/// Dart's `String.compareTo`: by UTF-16 code units. Negative, zero or
/// positive.
public func compareUTF16(_ a: String, _ b: String) -> Int {
    var x = a.utf16.makeIterator(), y = b.utf16.makeIterator()
    while true {
        switch (x.next(), y.next()) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case let (p?, q?): if p != q { return p < q ? -1 : 1 }
        }
    }
}

/// Where `needle` first occurs in `haystack` at or after `from`, both UTF-16;
/// -1 if it doesn't. Dart's `String.indexOf`.
func utf16Index(of needle: [UInt16], in haystack: [UInt16], from: Int = 0) -> Int {
    if needle.isEmpty { return from <= haystack.count ? from : -1 }
    guard haystack.count >= needle.count else { return -1 }
    var i = max(from, 0)
    while i <= haystack.count - needle.count {
        if haystack[i] == needle[0] {
            var k = 1
            while k < needle.count && haystack[i + k] == needle[k] { k += 1 }
            if k == needle.count { return i }
        }
        i += 1
    }
    return -1
}

/// Dart's `String.contains` for a string: code units, not characters.
func utf16Contains(_ haystack: String, _ needle: String) -> Bool {
    utf16Index(of: Array(needle.utf16), in: Array(haystack.utf16)) >= 0
}

/// A Dart-style comparison of two values: negative, zero or positive.
@inlinable func compareValues<T: Comparable>(_ a: T, _ b: T) -> Int {
    a < b ? -1 : (b < a ? 1 : 0)
}
