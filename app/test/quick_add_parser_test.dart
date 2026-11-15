import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/dates.dart';
import 'package:opentodo/domain/quick_add_parser.dart';

// Sunday, 15 November 2026, 10:00.
final now = DateTime(2026, 11, 15, 10);

void expectParse(
  String input, {
  required String title,
  String? date,
  String? time,
  List<String> tags = const [],
  int? priority,
}) {
  final r = parseQuickAdd(input, now);
  expect(r.title, title, reason: 'title of "$input"');
  expect(r.date == null ? null : dateKey(r.date!), date, reason: 'date of "$input"');
  expect(
    r.time == null
        ? null
        : '${(r.time! ~/ 60).toString().padLeft(2, '0')}:${(r.time! % 60).toString().padLeft(2, '0')}',
    time,
    reason: 'time of "$input"',
  );
  expect(r.tags, tags, reason: 'tags of "$input"');
  expect(r.priority, priority, reason: 'priority of "$input"');
}

void main() {
  test('plain text has no date', () {
    expectParse('买牛奶', title: '买牛奶');
    expectParse('  ', title: '');
  });

  group('relative days', () {
    test('今天 明天 后天 大后天', () {
      expectParse('今天交报告', title: '交报告', date: '2026-11-15');
      expectParse('明天交报告', title: '交报告', date: '2026-11-16');
      expectParse('后天交报告', title: '交报告', date: '2026-11-17');
      expectParse('大后天交报告', title: '交报告', date: '2026-11-18');
    });

    test('今晚 and 明早 carry a default time', () {
      expectParse('今晚 看电影', title: '看电影', date: '2026-11-15', time: '20:00');
      expectParse('明早 跑步', title: '跑步', date: '2026-11-16', time: '08:00');
      expectParse('今晚8点 看电影', title: '看电影', date: '2026-11-15', time: '20:00');
    });

    test('N天后', () {
      expectParse('3天后 复查', title: '复查', date: '2026-11-18');
      expectParse('两周后复查', title: '复查', date: '2026-11-29');
    });
  });

  group('weekdays (today is Sunday)', () {
    test('周X is the next one, today included', () {
      expectParse('周三交周报', title: '交周报', date: '2026-11-18');
      expectParse('星期天 休息', title: '休息', date: '2026-11-15');
      expectParse('礼拜五聚餐', title: '聚餐', date: '2026-11-20');
    });

    test('下周X and 这周X use Monday-start weeks', () {
      expectParse('下周一 项目评审', title: '项目评审', date: '2026-11-16');
      expectParse('下下周二 复盘', title: '复盘', date: '2026-11-24');
      expectParse('这周三 已经过了', title: '已经过了', date: '2026-11-11');
    });

    test('下周 alone is next Monday; 周末 is Saturday or today', () {
      expectParse('下周 开会', title: '开会', date: '2026-11-16');
      expectParse('周末 大扫除', title: '大扫除', date: '2026-11-15');
      expectParse('下周末 爬山', title: '爬山', date: '2026-11-21');
    });
  });

  group('calendar dates', () {
    test('month and day', () {
      expectParse('11月20日交房租', title: '交房租', date: '2026-11-20');
      expectParse('十二月一号 体检', title: '体检', date: '2026-12-01');
      expectParse('1月3日 回家', title: '回家', date: '2027-01-03');
      expectParse('12/25 圣诞', title: '圣诞', date: '2026-12-25');
      expectParse('2027年2月1日 续签', title: '续签', date: '2027-02-01');
    });

    test('day of month', () {
      expectParse('20号 还信用卡', title: '还信用卡', date: '2026-11-20');
      expectParse('10号 交水费', title: '交水费', date: '2026-12-10');
    });

    test('impossible dates are left as text', () {
      expectParse('2月30日', title: '2月30日');
    });
  });

  group('times', () {
    test('with a period', () {
      expectParse('明天下午3点开会', title: '开会', date: '2026-11-16', time: '15:00');
      expectParse('晨会 今天上午9点', title: '晨会', date: '2026-11-15', time: '09:00');
      expectParse('中午12点半 吃饭', title: '吃饭', date: '2026-11-15', time: '12:30');
      expectParse('晚上十点 睡觉', title: '睡觉', date: '2026-11-15', time: '22:00');
      expectParse('下午3点15分 电话', title: '电话', date: '2026-11-15', time: '15:15');
      expectParse('凌晨1点 收衣服', title: '收衣服', date: '2026-11-15', time: '01:00');
    });

    test('without a period, 1-6 means the afternoon', () {
      expectParse('3点开会', title: '开会', date: '2026-11-15', time: '15:00');
      expectParse('9:00 晨会', title: '晨会', date: '2026-11-15', time: '09:00');
      expectParse('8点一刻 出门', title: '出门', date: '2026-11-15', time: '08:15');
    });

    test('am and pm', () {
      expectParse('meeting 3pm', title: 'meeting', date: '2026-11-15', time: '15:00');
      expectParse('call 9:30am', title: 'call', date: '2026-11-15', time: '09:30');
    });

    test('一点点 is not a time', () {
      expectParse('吃一点点东西', title: '吃一点点东西');
    });
  });

  group('tags and priority', () {
    test('tags are removed from the title', () {
      expectParse('买机票 #出行', title: '买机票', tags: ['出行']);
      expectParse('#读书 读完一本书 #自我提升',
          title: '读完一本书', tags: ['读书', '自我提升']);
    });

    test('# inside a word is not a tag', () {
      expectParse('买C#的书', title: '买C#的书');
    });

    test('priority', () {
      expectParse('交税 !高', title: '交税', priority: 3);
      expectParse('交税 ！中', title: '交税', priority: 2);
      expectParse('交税 !1', title: '交税', priority: 1);
      expectParse('加油!', title: '加油!');
    });

    test('everything together', () {
      expectParse('明天下午3点开会 #工作 !高',
          title: '开会', date: '2026-11-16', time: '15:00', tags: ['工作'], priority: 3);
    });
  });

  test('tokens mark the recognised text', () {
    final r = parseQuickAdd('明天下午3点开会 #工作', now);
    expect(r.tokens.map((t) => (t.start, t.end, t.kind)).toList(), [
      (0, 2, QuickAddTokenKind.date),
      (2, 6, QuickAddTokenKind.time),
      (9, 12, QuickAddTokenKind.tag),
    ]);
  });

  test('parseNumber', () {
    expect(parseNumber('3'), 3);
    expect(parseNumber('十'), 10);
    expect(parseNumber('十一'), 11);
    expect(parseNumber('二十'), 20);
    expect(parseNumber('三十一'), 31);
    expect(parseNumber('两'), 2);
    expect(parseNumber('abc'), isNull);
  });
}
