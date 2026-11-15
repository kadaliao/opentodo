/// Pinyin for Chinese text: sorting titles in pinyin order, and finding
/// 周报 by typing `zhoubao`, `zb` or `zhoub`.
///
/// Each character has one reading from the table (generated, see
/// `tool/pinyin_table.swift`), plus the other common readings of the
/// polyphones listed in [_polyphones], so `yinhang` finds 银行. Readings are
/// toneless, ü written v (a `u` typed matches it too).
library;

import 'pinyin_table.dart';

/// Every reading of common polyphones (多音字); the first is the one used
/// for sorting, where it differs from the table's.
const _polyphones = <String, List<String>>{
  '长': ['chang', 'zhang'],
  '地': ['di', 'de'],
  '茄': ['qie', 'jia'],
  '行': ['xing', 'hang'],
  '重': ['zhong', 'chong'],
  '还': ['hai', 'huan'],
  '都': ['dou', 'du'],
  '的': ['de', 'di'],
  '得': ['de', 'dei'],
  '了': ['le', 'liao'],
  '乐': ['le', 'yue'],
  '觉': ['jue', 'jiao'],
  '会': ['hui', 'kuai'],
  '朝': ['chao', 'zhao'],
  '调': ['diao', 'tiao'],
  '数': ['shu', 'shuo'],
  '着': ['zhe', 'zhao', 'zhuo'],
  '便': ['bian', 'pian'],
  '藏': ['cang', 'zang'],
  '传': ['chuan', 'zhuan'],
  '弹': ['dan', 'tan'],
  '差': ['cha', 'chai', 'ci'],
  '和': ['he', 'huo', 'hu'],
  '降': ['jiang', 'xiang'],
  '角': ['jiao', 'jue'],
  '卡': ['ka', 'qia'],
  '落': ['luo', 'la', 'lao'],
  '没': ['mei', 'mo'],
  '省': ['sheng', 'xing'],
  '校': ['xiao', 'jiao'],
  '薄': ['bao', 'bo'],
  '称': ['cheng', 'chen'],
  '系': ['xi', 'ji'],
  '血': ['xue', 'xie'],
  '盛': ['sheng', 'cheng'],
  '参': ['can', 'shen', 'cen'],
  '单': ['dan', 'shan', 'chan'],
  '仇': ['chou', 'qiu'],
  '大': ['da', 'dai'],
  '给': ['gei', 'ji'],
  '似': ['si', 'shi'],
  '区': ['qu', 'ou'],
  '期': ['qi', 'ji'],
  '露': ['lu', 'lou'],
  '解': ['jie', 'xie'],
  '车': ['che', 'ju'],
  '哪': ['na', 'nei'],
  '那': ['na', 'nei'],
  '壳': ['ke', 'qiao'],
  '剥': ['bo', 'bao'],
  '识': ['shi', 'zhi'],
  '熟': ['shu', 'shou'],
  '色': ['se', 'shai'],
  '塞': ['sai', 'se'],
  '恶': ['e', 'wu'],
  '厦': ['sha', 'xia'],
  '率': ['lv', 'shuai'],
  '囤': ['dun', 'tun'],
  '胖': ['pang', 'pan'],
  '劲': ['jin', 'jing'],
  '番': ['fan', 'pan'],
  '粘': ['zhan', 'nian'],
  '扎': ['zha', 'za'],
  '咖': ['ka', 'ga'],
  '尾': ['wei', 'yi'],
  '秘': ['mi', 'bi'],
  '泊': ['po', 'bo'],
  '模': ['mo', 'mu'],
  '曾': ['ceng', 'zeng'],
  '仔': ['zi', 'zai'],
  '奇': ['qi', 'ji'],
  '抹': ['mo', 'ma'],
  '宿': ['su', 'xiu'],
  '亲': ['qin', 'qing'],
  '圈': ['quan', 'juan'],
  '绿': ['lv', 'lu'],
  '六': ['liu', 'lu'],
};

final _byCodePoint = {
  for (final e in _polyphones.entries) e.key.runes.first: e.value,
};

/// The readings of the character [codePoint], most common first; empty
/// for anything that isn't a Chinese character.
List<String> pinyinReadings(int codePoint) {
  final known = _byCodePoint[codePoint];
  if (known != null) return known;
  final i = codePoint - pinyinFirst;
  if (i < 0 || i * 2 + 1 >= pinyinCodes.length) {
    return codePoint == 0x3007 ? const ['ling'] : const []; // 〇
  }
  final n = pinyinAlphabet.indexOf(pinyinCodes[i * 2]) * pinyinAlphabet.length +
      pinyinAlphabet.indexOf(pinyinCodes[i * 2 + 1]);
  return n <= 0 ? const [] : [pinyinSyllables[n]];
}

/// Whether [text] has any Chinese character.
bool hasHan(String text) => text.runes.any((r) => pinyinReadings(r).isNotEmpty);

final _keys = <String, String>{};

/// [text] as it sorts: each Chinese character spelled in pinyin, the rest
/// in lower case. 爱 sorts with `ai`, between `ah` and `aj`.
String pinyinSortKey(String text) {
  final cached = _keys[text];
  if (cached != null) return cached;
  final out = StringBuffer();
  for (final r in text.runes) {
    final p = pinyinReadings(r);
    out.write(p.isEmpty ? String.fromCharCode(r).toLowerCase() : p.first);
  }
  if (_keys.length > 4000) _keys.clear();
  return _keys[text] = out.toString();
}

/// Titles in pinyin order (A–Z, Chinese and Latin together); where two
/// spell the same, by their characters.
int comparePinyin(String a, String b) {
  final c = pinyinSortKey(a).compareTo(pinyinSortKey(b));
  return c != 0 ? c : a.compareTo(b);
}

final _letters = RegExp(r'^[a-z]+$');

/// Where [term] (lower case, letters only) is spelled in [text]: each
/// Chinese character can be typed as its whole pinyin or the start of it
/// (`zb`, `zhoub`, `zhoubao` for 周报); anything else as itself, ignoring
/// case; spaces inside the text can be left out. Returns the character
/// ranges `[start, end)`, not overlapping, left to right; empty when it
/// isn't there or the term isn't letters.
List<(int, int)> pinyinRanges(String text, String term) {
  if (term.isEmpty || !_letters.hasMatch(term)) return const [];
  // Code units, so the ranges index the string as highlighting does; a
  // character outside the BMP is never Chinese here and matches nothing.
  final units = text.toLowerCase();
  if (units.length != text.length) return const [];
  final failed = <int>{};

  // The end of a match of term[j..] starting at text[i], or -1.
  int match(int i, int j) {
    if (j == term.length) return i;
    if (i >= units.length) return -1;
    final key = i * (term.length + 1) + j;
    if (failed.contains(key)) return -1;
    final c = units.codeUnitAt(i);
    var end = -1;
    final readings = pinyinReadings(c);
    if (readings.isNotEmpty) {
      for (final p in readings) {
        // The longest typed part of this reading first.
        var k = 0;
        while (k < p.length && j + k < term.length && _same(term.codeUnitAt(j + k), p.codeUnitAt(k))) {
          k++;
        }
        for (; k >= 1 && end < 0; k--) {
          end = match(i + 1, j + k);
        }
        if (end >= 0) break;
      }
    } else if (c == term.codeUnitAt(j)) {
      end = match(i + 1, j + 1);
    } else if (j > 0 && (c == 0x20 || c == 0x3000)) {
      end = match(i + 1, j);
    }
    if (end < 0) failed.add(key);
    return end;
  }

  final out = <(int, int)>[];
  for (var i = 0; i < units.length;) {
    final end = match(i, 0);
    if (end > i) {
      out.add((i, end));
      i = end;
    } else {
      i++;
    }
  }
  return out;
}

/// A typed letter against a reading's: `u` also stands for ü (v).
bool _same(int typed, int reading) =>
    typed == reading || (typed == 0x75 && reading == 0x76);
