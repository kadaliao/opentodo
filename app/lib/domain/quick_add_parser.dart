/// Parses the quick-add line: 明天下午3点开会 #工作 !高 becomes the title 开会,
/// tomorrow at 15:00, tag 工作 and high priority; 每周一9点例会 repeats;
/// 下午3点到5点 is a span.
/// Matched spans are returned so the input field can highlight them as the
/// person types.
library;

import 'dates.dart';
import 'recurrence.dart';

enum QuickAddTokenKind { date, time, tag, priority, repeat }

class QuickAddToken {
  const QuickAddToken(this.start, this.end, this.kind);

  final int start;
  final int end;
  final QuickAddTokenKind kind;

  @override
  String toString() => '$kind[$start,$end)';
}

class QuickAddResult {
  const QuickAddResult({
    required this.title,
    required this.date,
    required this.time,
    required this.tags,
    required this.priority,
    required this.tokens,
    this.repeat,
    this.duration,
  });

  final String title;

  /// For a repeating task without a date of its own, its first occurrence.
  final DateTime? date;

  /// Minutes after midnight.
  final int? time;

  /// Minutes from [time] to the end of a span (下午3点到5点: 120).
  final int? duration;
  final List<String> tags;
  final int? priority;
  final List<QuickAddToken> tokens;
  final RepeatRule? repeat;
}

const _num = r'(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})';
const _period = r'凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里|夜晚|早|晚';

const _cnDigits = {
  '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, //
  '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
};

/// 3 / 十一 / 二十三 / 两 → int.
int? parseNumber(String s) {
  final n = int.tryParse(s);
  if (n != null) return n;
  if (s.isEmpty) return null;
  final i = s.indexOf('十');
  if (i == -1) return s.length == 1 ? _cnDigits[s] : null;
  final tens = i == 0 ? 1 : _cnDigits[s.substring(0, i)];
  final rest = s.substring(i + 1);
  final ones = rest.isEmpty ? 0 : _cnDigits[rest];
  if (tens == null || ones == null) return null;
  return tens * 10 + ones;
}

int _weekdayNumber(String s) => switch (s) {
      '一' || '1' => 1,
      '二' || '2' => 2,
      '三' || '3' => 3,
      '四' || '4' => 4,
      '五' || '5' => 5,
      '六' || '6' => 6,
      _ => 7, // 日 / 天 / 7
    };

DateTime? _validDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  return date.month == m ? date : null; // rejects 2月30日
}

/// A date found in the text, plus what it says about the time of day.
class _DateHit {
  _DateHit(this.match, this.date, {this.periodHint, this.defaultTime});

  final RegExpMatch match;
  final DateTime date;
  final String? periodHint;
  final int? defaultTime;
}

typedef _DateRule = _DateHit? Function(RegExpMatch m, DateTime today);

final List<(RegExp, _DateRule)> _dateRules = [
  // 2026年11月18日 / 2026-11-18 / 2026/11/18
  (
    RegExp(r'(\d{4})\s*[年/\-.]\s*(\d{1,2})\s*[月/\-.]\s*(\d{1,2})\s*[日号]?'),
    (m, today) {
      final d = _validDate(
          int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      return d == null ? null : _DateHit(m, d);
    },
  ),
  // 11月18日 / 十一月十八号: this year, or next year if already past.
  (
    RegExp('($_num)\\s*月\\s*($_num)\\s*[日号]?'),
    (m, today) {
      final mo = parseNumber(m[1]!), day = parseNumber(m[2]!);
      if (mo == null || day == null) return null;
      var d = _validDate(today.year, mo, day);
      if (d != null && d.isBefore(today)) d = _validDate(today.year + 1, mo, day);
      return d == null ? null : _DateHit(m, d);
    },
  ),
  // 11/18
  (
    RegExp(r'(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])'),
    (m, today) {
      var d = _validDate(today.year, int.parse(m[1]!), int.parse(m[2]!));
      if (d != null && d.isBefore(today)) {
        d = _validDate(today.year + 1, int.parse(m[1]!), int.parse(m[2]!));
      }
      return d == null ? null : _DateHit(m, d);
    },
  ),
  (
    RegExp(r'大后天|后天|明天|明日|明儿|今天|今日|今晚|今早|明晚|明早'),
    (m, today) => switch (m[0]!) {
          '今晚' => _DateHit(m, today, periodHint: '晚上', defaultTime: 20 * 60),
          '今早' => _DateHit(m, today, periodHint: '早上', defaultTime: 8 * 60),
          '明晚' => _DateHit(m, addDays(today, 1),
              periodHint: '晚上', defaultTime: 20 * 60),
          '明早' => _DateHit(m, addDays(today, 1),
              periodHint: '早上', defaultTime: 8 * 60),
          '明天' || '明日' || '明儿' => _DateHit(m, addDays(today, 1)),
          '后天' => _DateHit(m, addDays(today, 2)),
          '大后天' => _DateHit(m, addDays(today, 3)),
          _ => _DateHit(m, today),
        },
  ),
  // 周五 / 下周一 / 这周三 / 下下周二 / 星期天
  (
    RegExp(r'(下下|下个?|这个?|本|上个?)?(?:周|星期|礼拜)([一二三四五六日天1-7])'),
    (m, today) {
      final wd = _weekdayNumber(m[2]!);
      final monday = startOfWeek(today);
      final d = switch (m[1]) {
        null => addDays(today, (wd - today.weekday) % 7),
        '这' || '这个' || '本' => addDays(monday, wd - 1),
        '下下' => addDays(monday, 14 + wd - 1),
        '上' || '上个' => addDays(monday, -7 + wd - 1),
        _ => addDays(monday, 7 + wd - 1),
      };
      return _DateHit(m, d);
    },
  ),
  // 3天后 / 两周后 / 1个月以后
  (
    RegExp('($_num)\\s*(天|个?星期|周|个?月)\\s*(?:后|之后|以后)'),
    (m, today) {
      final n = parseNumber(m[1]!);
      if (n == null) return null;
      final unit = m[2]!;
      if (unit.endsWith('月')) {
        return _DateHit(m, DateTime(today.year, today.month + n, today.day));
      }
      final days = unit == '天' ? n : n * 7;
      return _DateHit(m, addDays(today, days));
    },
  ),
  // 周末 / 下周末 → Saturday
  (
    RegExp(r'(下个?)?周末'),
    (m, today) {
      final sat = addDays(startOfWeek(today), 5);
      if (m[1] != null) return _DateHit(m, addDays(sat, 7));
      // On a Sunday, 周末 is today.
      return _DateHit(m, sat.isBefore(today) ? today : sat);
    },
  ),
  // 下周 alone → next Monday
  (
    RegExp(r'下个?(?:周|星期|礼拜)(?![一二三四五六日天1-7末])'),
    (m, today) => _DateHit(m, addDays(startOfWeek(today), 7)),
  ),
  // 20号: this month, or next month if already past.
  (
    RegExp(r'(?<!\d)(\d{1,2})\s*号'),
    (m, today) {
      final day = int.parse(m[1]!);
      var d = _validDate(today.year, today.month, day);
      if (d != null && d.isBefore(today)) {
        d = _validDate(today.year, today.month + 1, day) ??
            _validDate(today.year, today.month + 2, day);
      }
      return d == null ? null : _DateHit(m, d);
    },
  ),
];

const _weekdayChars = '一二三四五六日天1-7';

/// 每天 / 每3天 / 每周一、三 / 每两周 / 工作日 / 每月15号 / 每月最后一天 / 每年3月8日 …
final List<(RegExp, RepeatRule? Function(RegExpMatch m))> _repeatRules = [
  // Always with 每, so 工作日志 or 天天向上 stay plain words.
  (RegExp(r'每天|每日'), (m) => RepeatRule.daily),
  (
    RegExp('每($_num)天'),
    (m) => switch (parseNumber(m[1]!)) {
          final n? when n > 0 => RepeatRule(Freq.daily, interval: n),
          _ => null,
        },
  ),
  (RegExp(r'每个?工作日'), (m) => RepeatRule.workdays),
  (RegExp(r'每个?周末'), (m) => RepeatRule.weekends),
  // 每周一 / 每周一三五 / 每周二、四 / 每个星期六
  (
    RegExp('每个?(?:周|星期|礼拜)([$_weekdayChars](?:[、,，和及与]?[$_weekdayChars])*)'),
    (m) {
      final days = {
        for (final c in m[1]!.split(''))
          if (RegExp('[$_weekdayChars]').hasMatch(c)) _weekdayNumber(c),
      }.toList()
        ..sort();
      return RepeatRule(Freq.weekly, weekdays: days);
    },
  ),
  (
    RegExp('每($_num)个?(?:周|星期|礼拜)'),
    (m) => switch (parseNumber(m[1]!)) {
          final n? when n > 0 => RepeatRule(Freq.weekly, interval: n),
          _ => null,
        },
  ),
  (RegExp(r'每个?(?:周|星期|礼拜)'), (m) => RepeatRule.weekly),
  (RegExp(r'每个?月(?:的)?最后一天'), (m) => const RepeatRule(Freq.monthly, monthDays: [-1])),
  (
    RegExp('每个?月(?:的)?($_num)\\s*[号日]'),
    (m) => switch (parseNumber(m[1]!)) {
          final n? when n >= 1 && n <= 31 => RepeatRule(Freq.monthly, monthDays: [n]),
          _ => null,
        },
  ),
  (
    RegExp('每($_num)个月'),
    (m) => switch (parseNumber(m[1]!)) {
          final n? when n > 0 => RepeatRule(Freq.monthly, interval: n),
          _ => null,
        },
  ),
  (RegExp(r'每个?月'), (m) => RepeatRule.monthly),
  (
    RegExp('每年(?:的)?($_num)\\s*月\\s*($_num)\\s*[日号]?'),
    (m) {
      final mo = parseNumber(m[1]!), day = parseNumber(m[2]!);
      if (mo == null || day == null || _validDate(2028, mo, day) == null) return null;
      return RepeatRule(Freq.yearly, month: mo, monthDays: [day]);
    },
  ),
  (RegExp(r'每年'), (m) => RepeatRule.yearly),
];

final _timeColon = RegExp('($_period)?\\s*(\\d{1,2})\\s*[:：]\\s*(\\d{2})');
final _timeDian = RegExp(
    '($_period)?\\s*($_num)\\s*[点时](?![点儿])(?:\\s*(半|一刻|三刻|(\\d{1,2})\\s*分?|([零一二三四五六七八九十]{1,3})\\s*分))?');
final _timeAmPm =
    RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);
final _rangeJoin = RegExp(r'\s*(?:到|至|-|~|～|—|－)\s*');
final _tag = RegExp(r'(?<!\S)#([^\s#]+)');
final _priority = RegExp(r'(?<!\S)[!！](高|中|低|[1-3])(?!\S)');

int? _hour24(int h, String? period) {
  switch (period) {
    case '下午' || '傍晚' || '晚上' || '夜里' || '夜晚' || '晚':
      if (h < 12) h += 12;
    case '中午':
      if (h < 6) h += 12;
    case '凌晨':
      if (h == 12) h = 0;
    case '上午' || '早上' || '早晨' || '早':
      break;
    default:
      // No period: 3点开会 means the afternoon.
      if (h >= 1 && h <= 6) h += 12;
  }
  return h >= 0 && h <= 23 ? h : null;
}

final _timeRules = [_timeAmPm, _timeColon, _timeDian];

/// The hour and minute a time match says, before 上午/下午 is applied;
/// [period] is what it named (`ampm` for am/pm, already applied).
({int hour, int minute, String? period})? _readTime(RegExp re, RegExpMatch m) {
  if (re == _timeAmPm) {
    final h = int.parse(m[1]!);
    if (h > 12) return null;
    final pm = m[3]!.toLowerCase() == 'pm';
    return (hour: h % 12 + (pm ? 12 : 0), minute: m[2] == null ? 0 : int.parse(m[2]!), period: 'ampm');
  }
  if (re == _timeColon) return (hour: int.parse(m[2]!), minute: int.parse(m[3]!), period: m[1]);
  final raw = parseNumber(m[2]!);
  final min = switch (m[3]) {
    null => 0,
    '半' => 30,
    '一刻' => 15,
    '三刻' => 45,
    _ => m[4] != null ? int.parse(m[4]!) : parseNumber(m[5]!),
  };
  if (raw == null || min == null) return null;
  return (hour: raw, minute: min, period: m[1]);
}

/// The end of 3点到5点, right after the start's match: minutes from the
/// start, and where the text ends. Without 上午/下午 the end is the first
/// reading after the start (上午11点到1点 ends at 13:00); one earlier than
/// the start runs past midnight (晚上10点到凌晨2点).
(int, int)? _spanEnd(String masked, int from, int start) {
  final join = _rangeJoin.matchAsPrefix(masked, from);
  if (join == null) return null;
  for (final re in _timeRules) {
    final m = re.matchAsPrefix(masked, join.end) as RegExpMatch?;
    if (m == null) continue;
    final t = _readTime(re, m);
    if (t == null || t.minute < 0 || t.minute > 59) return null;
    var h = switch (t.period) {
      'ampm' => t.hour,
      null => t.hour <= 23 ? t.hour : null,
      final p => _hour24(t.hour, p),
    };
    if (h == null) return null;
    if (t.period == null && h < 12 && h * 60 + t.minute <= start) h += 12;
    var end = h * 60 + t.minute;
    if (end <= start) end += 24 * 60;
    final duration = end - start;
    if (duration <= 0 || duration > 24 * 60) return null;
    return (duration, m.end);
  }
  return null;
}

QuickAddResult parseQuickAdd(String input, DateTime now) {
  final today = dateOnly(now);
  final tokens = <QuickAddToken>[];
  var masked = input;

  void consume(int start, int end, QuickAddTokenKind kind) {
    tokens.add(QuickAddToken(start, end, kind));
    masked = masked.replaceRange(start, end, '\u0000' * (end - start));
  }

  // Tags and priority first, so their text isn't read as a date.
  final tags = <String>[];
  for (final m in _tag.allMatches(masked).toList()) {
    tags.add(m[1]!);
    consume(m.start, m.end, QuickAddTokenKind.tag);
  }
  int? priority;
  final pm = _priority.firstMatch(masked);
  if (pm != null) {
    priority = switch (pm[1]) { '高' || '3' => 3, '中' || '2' => 2, _ => 1 };
    consume(pm.start, pm.end, QuickAddTokenKind.priority);
  }

  // Repeats before dates, so 每周一 isn't read as 周一.
  RepeatRule? repeat;
  for (final (re, rule) in _repeatRules) {
    for (final m in re.allMatches(masked)) {
      repeat = rule(m);
      if (repeat != null) {
        consume(m.start, m.end, QuickAddTokenKind.repeat);
        break;
      }
    }
    if (repeat != null) break;
  }

  _DateHit? dateHit;
  for (final (re, rule) in _dateRules) {
    for (final m in re.allMatches(masked)) {
      dateHit = rule(m, today);
      if (dateHit != null) break;
    }
    if (dateHit != null) break;
  }
  if (dateHit != null) {
    consume(dateHit.match.start, dateHit.match.end, QuickAddTokenKind.date);
  }

  int? time, duration;
  final periodHint = dateHit?.periodHint;
  for (final re in _timeRules) {
    final m = re.firstMatch(masked);
    if (m == null) continue;
    final t = _readTime(re, m);
    final h = t == null
        ? null
        : (t.period == 'ampm' ? t.hour : _hour24(t.hour, t.period ?? periodHint));
    if (h != null && t!.minute >= 0 && t.minute < 60) {
      time = h * 60 + t.minute;
      var end = m.end;
      if (_spanEnd(masked, m.end, time) case (final d, final to)) {
        duration = d;
        end = to;
      }
      consume(m.start, end, QuickAddTokenKind.time);
      break;
    }
  }

  time ??= dateHit?.defaultTime;
  var date = dateHit?.date ??
      (repeat != null ? firstOccurrence(repeat, today) : (time != null ? today : null));
  // 每天8点吃药 typed at 10:00 starts tomorrow, not overdue.
  if (dateHit == null &&
      repeat != null &&
      time != null &&
      date == today &&
      time <= now.hour * 60 + now.minute) {
    date = nextOccurrence(repeat, today) ?? date;
  }

  tokens.sort((a, b) => a.start.compareTo(b.start));
  final buf = StringBuffer();
  var pos = 0;
  for (final t in tokens) {
    buf.write(input.substring(pos, t.start));
    buf.write(' ');
    pos = t.end;
  }
  buf.write(input.substring(pos));
  final title = buf
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,，、;；]+|[\s,，、;；]+$'), '');

  return QuickAddResult(
    title: title,
    date: date,
    time: time,
    tags: tags,
    priority: priority,
    tokens: tokens,
    repeat: repeat,
    duration: duration,
  );
}
