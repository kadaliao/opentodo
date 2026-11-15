/// Repeat rules: the part of iCalendar's RRULE (RFC 5545) a to-do app needs.
///
/// A repeating task is one row whose date moves forward each time it is
/// completed; the rule says where it moves to. Rules are stored as RRULE
/// text (`FREQ=WEEKLY;BYDAY=MO,WE`) so they can be exported to calendars
/// later. Parts the rule leaves out (which weekday, which day of the month)
/// come from the task's current date, as DTSTART does in iCalendar.
library;

import 'dates.dart';

enum Freq { daily, weekly, monthly, yearly }

/// What the next date is counted from when a repeating task is completed.
abstract final class RepeatFrom {
  /// The task's own date: 每周一 stays on Mondays.
  static const dueDate = 0;

  /// The day it was completed: 完成后每3天.
  static const completion = 1;
}

const _dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const _workdays = [1, 2, 3, 4, 5];
const _weekend = [6, 7];

class RepeatRule {
  const RepeatRule(
    this.freq, {
    this.interval = 1,
    this.weekdays = const [],
    this.monthDays = const [],
    this.nthWeekday,
    this.month,
    this.until,
    this.count,
  });

  final Freq freq;

  /// Every [interval] days / weeks / months / years.
  final int interval;

  /// WEEKLY: 1 = Monday … 7 = Sunday, sorted. Empty: the task's weekday.
  final List<int> weekdays;

  /// MONTHLY / YEARLY: days of the month, -1 for the last. Empty: the task's
  /// day. Months without that day are skipped, as in iCalendar.
  final List<int> monthDays;

  /// MONTHLY / YEARLY: the nth weekday of the month (n = -1 for the last),
  /// such as the second Tuesday.
  final ({int n, int weekday})? nthWeekday;

  /// YEARLY: 1–12. Null: the task's month.
  final int? month;

  /// Last date the series may land on, inclusive.
  final DateTime? until;

  /// Occurrences left, the current one included. Each completion uses one up.
  final int? count;

  static const daily = RepeatRule(Freq.daily);
  static const weekly = RepeatRule(Freq.weekly);
  static const monthly = RepeatRule(Freq.monthly);
  static const yearly = RepeatRule(Freq.yearly);
  static const workdays = RepeatRule(Freq.weekly, weekdays: _workdays);
  static const weekends = RepeatRule(Freq.weekly, weekdays: _weekend);

  /// Null for empty or unusable text (an unknown FREQ, say, from a newer app).
  static RepeatRule? tryParse(String? text) {
    if (text == null) return null;
    var s = text.trim();
    if (s.toUpperCase().startsWith('RRULE:')) s = s.substring(6);
    if (s.isEmpty) return null;
    final parts = <String, String>{};
    for (final p in s.split(';')) {
      final i = p.indexOf('=');
      if (i > 0) parts[p.substring(0, i).trim().toUpperCase()] = p.substring(i + 1).trim();
    }
    final freq = switch (parts['FREQ']?.toUpperCase()) {
      'DAILY' => Freq.daily,
      'WEEKLY' => Freq.weekly,
      'MONTHLY' => Freq.monthly,
      'YEARLY' => Freq.yearly,
      _ => null,
    };
    if (freq == null) return null;
    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;

    final weekdays = <int>{};
    ({int n, int weekday})? nth;
    for (final d in (parts['BYDAY'] ?? '').split(',')) {
      final m = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(d.trim().toUpperCase());
      if (m == null) continue;
      final wd = _dayCodes.indexOf(m[2]!) + 1;
      final n = m[1] == null ? null : int.parse(m[1]!);
      if (n == null) {
        weekdays.add(wd);
      } else if (n != 0 && n >= -5 && n <= 5) {
        nth ??= (n: n, weekday: wd);
      }
    }
    final monthDays = <int>{
      for (final d in (parts['BYMONTHDAY'] ?? '').split(','))
        if (int.tryParse(d.trim()) case final n? when n != 0 && n >= -1 && n <= 31) n,
    };
    final month = int.tryParse(parts['BYMONTH']?.split(',').first ?? '');
    final count = int.tryParse(parts['COUNT'] ?? '');
    return RepeatRule(
      freq,
      interval: interval < 1 ? 1 : interval,
      weekdays: freq == Freq.weekly ? (weekdays.toList()..sort()) : const [],
      monthDays: freq == Freq.monthly || freq == Freq.yearly
          ? (monthDays.toList()..sort(_compareMonthDays))
          : const [],
      nthWeekday: freq == Freq.monthly || freq == Freq.yearly ? nth : null,
      month: freq == Freq.yearly && month != null && month >= 1 && month <= 12 ? month : null,
      until: _parseUntil(parts['UNTIL']),
      count: count != null && count > 0 ? count : null,
    );
  }

  static DateTime? _parseUntil(String? s) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(s ?? '');
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  /// RRULE text, parts in a fixed order so equal rules give equal text.
  @override
  String toString() {
    final parts = ['FREQ=${freq.name.toUpperCase()}'];
    if (interval > 1) parts.add('INTERVAL=$interval');
    if (month != null) parts.add('BYMONTH=$month');
    if (monthDays.isNotEmpty) parts.add('BYMONTHDAY=${monthDays.join(',')}');
    if (weekdays.isNotEmpty) {
      parts.add('BYDAY=${weekdays.map((d) => _dayCodes[d - 1]).join(',')}');
    } else if (nthWeekday case final nth?) {
      parts.add('BYDAY=${nth.n}${_dayCodes[nth.weekday - 1]}');
    }
    if (until case final u?) {
      parts.add('UNTIL=${u.year.toString().padLeft(4, '0')}'
          '${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}');
    }
    if (count != null) parts.add('COUNT=$count');
    return parts.join(';');
  }

  @override
  bool operator ==(Object other) => other is RepeatRule && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;

  RepeatRule copyWith({
    int? interval,
    List<int>? weekdays,
    List<int>? monthDays,
    ({int n, int weekday})? Function()? nthWeekday,
    int? Function()? month,
    DateTime? Function()? until,
    int? Function()? count,
  }) =>
      RepeatRule(
        freq,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        monthDays: monthDays ?? this.monthDays,
        nthWeekday: nthWeekday == null ? this.nthWeekday : nthWeekday(),
        month: month == null ? this.month : month(),
        until: until == null ? this.until : until(),
        count: count == null ? this.count : count(),
      );

  /// The rule without its end (until / count).
  RepeatRule get open => copyWith(until: () => null, count: () => null);

  bool get _usesTaskDate => switch (freq) {
        Freq.daily => true,
        Freq.weekly => weekdays.isEmpty,
        Freq.monthly => monthDays.isEmpty && nthWeekday == null,
        Freq.yearly => monthDays.isEmpty && nthWeekday == null,
      };
}

int _compareMonthDays(int a, int b) => (a < 0 ? 99 : a).compareTo(b < 0 ? 99 : b);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The [n]th [weekday] of a month (n = -1 for the last), or null if the month
/// hasn't got one (a fifth Monday, say).
DateTime? nthWeekdayOfMonth(int year, int month, int n, int weekday) {
  if (n > 0) {
    final first = DateTime(year, month);
    final d = 1 + (weekday - first.weekday) % 7 + (n - 1) * 7;
    return d <= daysInMonth(year, month) ? DateTime(year, month, d) : null;
  }
  final lastDay = daysInMonth(year, month);
  final last = DateTime(year, month, lastDay);
  final d = lastDay - (last.weekday - weekday) % 7 + (n + 1) * 7;
  return d >= 1 ? DateTime(year, month, d) : null;
}

/// Dates the rule allows in one month, in order. [anchor] fills in whatever
/// the rule leaves out.
List<DateTime> _monthCandidates(RepeatRule r, int year, int month, DateTime anchor) {
  final ym = DateTime(year, month); // normalises month overflow
  if (r.nthWeekday case final nth?) {
    final d = nthWeekdayOfMonth(ym.year, ym.month, nth.n, nth.weekday);
    return d == null ? const [] : [d];
  }
  final last = daysInMonth(ym.year, ym.month);
  final days = r.monthDays.isEmpty ? [anchor.day] : r.monthDays;
  final out = <DateTime>[
    for (final d in days)
      if (d == -1)
        DateTime(ym.year, ym.month, last)
      else if (d <= last)
        DateTime(ym.year, ym.month, d),
  ]..sort();
  return out;
}

/// The first date after [anchor] the rule lands on, ignoring its end. The
/// anchor also fixes the phase: with an interval of two, which weeks count.
DateTime? _stepAfter(RepeatRule r, DateTime anchor) {
  anchor = dateOnly(anchor);
  switch (r.freq) {
    case Freq.daily:
      return addDays(anchor, r.interval);
    case Freq.weekly:
      final days = r.weekdays.isEmpty ? [anchor.weekday] : r.weekdays;
      final monday = startOfWeek(anchor);
      for (final weeks in [0, r.interval]) {
        for (final wd in days) {
          final d = addDays(monday, weeks * 7 + wd - 1);
          if (d.isAfter(anchor)) return d;
        }
      }
      return null;
    case Freq.monthly:
      // A bound in case the rule names a day no month has.
      for (var k = 0; k <= 1200; k += r.interval) {
        for (final d in _monthCandidates(r, anchor.year, anchor.month + k, anchor)) {
          if (d.isAfter(anchor)) return d;
        }
      }
      return null;
    case Freq.yearly:
      final month = r.month ?? anchor.month;
      for (var k = 0; k <= 400; k += r.interval) {
        // _monthCandidates skips Feb 29 in other years, as iCalendar does.
        for (final d in _monthCandidates(r, anchor.year + k, month, anchor)) {
          if (d.year == anchor.year + k && d.isAfter(anchor)) return d;
        }
      }
      return null;
  }
}

/// The occurrence after [date], or null when the series has ended there.
DateTime? nextOccurrence(RepeatRule rule, DateTime date) {
  if (rule.count != null && rule.count! <= 1) return null;
  final next = _stepAfter(rule, date);
  if (next == null) return null;
  if (rule.until != null && next.isAfter(rule.until!)) return null;
  return next;
}

/// The occurrences after [date], in order, as long as the series runs: the
/// dates a calendar shows ahead of a repeating task. [rule]'s count includes
/// [date] itself.
Iterable<DateTime> occurrencesAfter(RepeatRule rule, DateTime date) sync* {
  var left = rule.count;
  var at = dateOnly(date);
  while (left == null || left > 1) {
    final next = _stepAfter(rule, at);
    if (next == null) return;
    if (rule.until != null && next.isAfter(rule.until!)) return;
    if (left != null) left--;
    at = next;
    yield next;
  }
}

/// Where a repeating task goes when one occurrence is done or skipped.
class RepeatAdvance {
  const RepeatAdvance(this.date, this.rule);

  /// The task's new date.
  final DateTime date;

  /// The rule to store with it: its count, if it has one, is used up by the
  /// occurrences passed over.
  final RepeatRule rule;
}

/// The next date for a repeating task finished (or skipped) on [today].
///
/// Counting from the due date, the task lands on the first occurrence after
/// both its date and today, so finishing an overdue daily task doesn't leave
/// another overdue copy behind. Counting from completion, the rule restarts
/// from today. Null when the series is over.
RepeatAdvance? advanceRepeat(
  RepeatRule rule,
  DateTime due, {
  required DateTime today,
  int repeatFrom = RepeatFrom.dueDate,
}) {
  today = dateOnly(today);
  due = dateOnly(due);
  var left = rule.count;
  var date = repeatFrom == RepeatFrom.completion ? today : due;
  // Generous bound: a daily task years overdue still gets there.
  for (var i = 0; i < 100000; i++) {
    if (left != null && left <= 1) return null;
    final next = _stepAfter(rule, date);
    if (next == null) return null;
    if (rule.until != null && next.isAfter(rule.until!)) return null;
    if (left != null) left--;
    date = next;
    if (date.isAfter(today) && date.isAfter(due)) {
      return RepeatAdvance(date, rule.copyWith(count: () => left));
    }
  }
  return null;
}

/// The first date on or after [from] the rule lands on: where a new task
/// typed as 每周一 starts.
DateTime firstOccurrence(RepeatRule rule, DateTime from) {
  from = dateOnly(from);
  if (rule._usesTaskDate) return from;
  return _stepAfter(rule.open, addDays(from, -1)) ?? from;
}

// ---- words ----

const _cnWeekday = ['一', '二', '三', '四', '五', '六', '日'];

String _weekdayList(List<int> days) => days.map((d) => _cnWeekday[d - 1]).join('、');

String _nthLabel(int n) => n == -1 ? '最后一个' : '第$n个';

String _monthDayLabel(int d) => d == -1 ? '最后一天' : '$d日';

/// 每天 / 每2周的周一、三 / 工作日 / 每月最后一天 / 每年11月15日 …
/// [date] is the task's date, which fills in what the rule leaves out.
String describeRepeat(RepeatRule r, DateTime date, {int repeatFrom = RepeatFrom.dueDate}) {
  final n = r.interval;

  final base = switch (r.freq) {
    Freq.daily => n == 1 ? '每天' : '每$n天',
    Freq.weekly when n == 1 && _sameDays(r.weekdays, _workdays) => '工作日',
    Freq.weekly when n == 1 && _sameDays(r.weekdays, _weekend) => '周末',
    Freq.weekly when n == 1 && r.weekdays.length == 7 => '每天',
    Freq.weekly => () {
        final days = '周${_weekdayList(r.weekdays.isEmpty ? [date.weekday] : r.weekdays)}';
        return n == 1 ? '每$days' : '每$n周的$days';
      }(),
    Freq.monthly => () {
        final which = r.nthWeekday != null
            ? '${_nthLabel(r.nthWeekday!.n)}周${_cnWeekday[r.nthWeekday!.weekday - 1]}'
            : (r.monthDays.isEmpty ? [date.day] : r.monthDays).map(_monthDayLabel).join('、');
        return n == 1 ? '每月$which' : '每$n个月的$which';
      }(),
    Freq.yearly => () {
        final m = r.month ?? date.month;
        final which = r.nthWeekday != null
            ? '$m月${_nthLabel(r.nthWeekday!.n)}周${_cnWeekday[r.nthWeekday!.weekday - 1]}'
            : '$m月${(r.monthDays.isEmpty ? [date.day] : r.monthDays).map(_monthDayLabel).join('、')}';
        return n == 1 ? '每年$which' : '每$n年的$which';
      }(),
  };
  final from = repeatFrom == RepeatFrom.completion ? '（按完成日期）' : '';
  final end = r.until != null
      ? '，至${r.until!.year}年${r.until!.month}月${r.until!.day}日'
      : (r.count != null ? '，还剩${r.count}次' : '');
  return '$base$from$end';
}

bool _sameDays(List<int> a, List<int> b) =>
    a.length == b.length && a.every(b.contains);
