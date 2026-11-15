/// China's public holidays and the weekend days worked in exchange (调休),
/// as the State Council's General Office announces them each year
/// (国务院办公厅关于××××年部分节假日安排的通知, usually in November). The
/// schedule isn't a rule that can be worked out, so it ships with the app:
/// when next year's notice is out, add it to [_schedules] and release.
library;

import 'dates.dart';

/// One holiday in a notice: the days off, and the weekend days worked.
class _Holiday {
  const _Holiday(this.name, this.from, this.to, [this.workdays = const []]);

  final String name;

  /// `MM-DD`, inclusive.
  final String from, to;

  /// `MM-DD`: weekend days worked in exchange (上班).
  final List<String> workdays;
}

const Map<int, List<_Holiday>> _schedules = {
  // 国办发明电〔2024〕12号
  2025: [
    _Holiday('元旦', '01-01', '01-01'),
    _Holiday('春节', '01-28', '02-04', ['01-26', '02-08']),
    _Holiday('清明节', '04-04', '04-06'),
    _Holiday('劳动节', '05-01', '05-05', ['04-27']),
    _Holiday('端午节', '05-31', '06-02'),
    _Holiday('国庆节、中秋节', '10-01', '10-08', ['09-28', '10-11']),
  ],
  // 国办发明电〔2025〕7号
  2026: [
    _Holiday('元旦', '01-01', '01-03', ['01-04']),
    _Holiday('春节', '02-15', '02-23', ['02-14', '02-28']),
    _Holiday('清明节', '04-04', '04-06'),
    _Holiday('劳动节', '05-01', '05-05', ['05-09']),
    _Holiday('端午节', '06-19', '06-21'),
    _Holiday('中秋节', '09-25', '09-27'),
    _Holiday('国庆节', '10-01', '10-07', ['09-20', '10-10']),
  ],
  // 国办发明电〔2026〕10号
  2027: [
    _Holiday('元旦', '01-01', '01-03'),
    _Holiday('春节', '02-05', '02-13', ['01-31', '02-14']),
    _Holiday('清明节', '04-03', '04-05'),
    _Holiday('劳动节', '05-01', '05-05', ['05-08']),
    _Holiday('端午节', '06-09', '06-09'),
    _Holiday('中秋节', '09-15', '09-15'),
    _Holiday('国庆节', '10-01', '10-07', ['09-26', '10-09']),
  ],
};

/// The years the app knows the schedule for.
Iterable<int> get holidayYears => _schedules.keys;

/// A day the schedule says something about: off for [name], or a weekend
/// day worked in exchange for it.
typedef HolidayDay = ({String name, bool off});

final Map<String, HolidayDay> _days = () {
  final out = <String, HolidayDay>{};
  for (final MapEntry(key: year, value: holidays) in _schedules.entries) {
    DateTime day(String md) => parseDateKey('$year-$md');
    for (final h in holidays) {
      for (var d = day(h.from); !d.isAfter(day(h.to)); d = addDays(d, 1)) {
        out[dateKey(d)] = (name: h.name, off: true);
      }
      for (final w in h.workdays) {
        out[dateKey(day(w))] = (name: h.name, off: false);
      }
    }
  }
  return out;
}();

/// Whether [date] is a public holiday (休) or a weekend day worked (班);
/// null for an ordinary day or a year without a schedule.
HolidayDay? holidayOn(DateTime date) => _days[dateKey(date)];

/// A working day by the schedule: Monday to Friday unless it's a holiday,
/// and the weekend days worked in exchange. Years without a schedule go by
/// the weekdays alone.
bool isWorkday(DateTime date) {
  final h = holidayOn(date);
  return h == null ? date.weekday <= DateTime.friday : !h.off;
}
