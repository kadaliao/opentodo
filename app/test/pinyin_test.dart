import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/pinyin.dart';

void main() {
  test('reads characters from the table and the polyphone list', () {
    int c(String s) => s.runes.first;
    expect(pinyinReadings(c('周')), ['zhou']);
    expect(pinyinReadings(c('报')), ['bao']);
    expect(pinyinReadings(c('女')), ['nv']);
    expect(pinyinReadings(c('长')), ['chang', 'zhang']);
    expect(pinyinReadings(c('〇')), ['ling']);
    expect(pinyinReadings(c('a')), isEmpty);
    expect(pinyinReadings(c('，')), isEmpty);
    expect(hasHan('写周报'), isTrue);
    expect(hasHan('report 1'), isFalse);
  });

  test('sorts Chinese and Latin titles together, A to Z', () {
    final titles = ['周报', 'apple', '爱好', 'Banana', '吃饭', '123', 'ah', 'aj', '长期目标'];
    titles.sort(comparePinyin);
    expect(titles, ['123', 'ah', '爱好', 'aj', 'apple', 'Banana', '长期目标', '吃饭', '周报']);
  });

  test('finds a title by its pinyin, initials or a mix', () {
    expect(pinyinRanges('写周报', 'zhoubao'), [(1, 3)]);
    expect(pinyinRanges('写周报', 'zb'), [(1, 3)]);
    expect(pinyinRanges('写周报', 'zhoub'), [(1, 3)]);
    expect(pinyinRanges('写周报', 'xzb'), [(0, 3)]);
    expect(pinyinRanges('写周报', 'zhb'), [(1, 3)]);
    expect(pinyinRanges('写周报', 'bz'), isEmpty);
    expect(pinyinRanges('去银行', 'yinhang'), [(1, 3)]);
    expect(pinyinRanges('去银行', 'yh'), [(1, 3)]);
    expect(pinyinRanges('买绿茶', 'lvcha'), [(1, 3)]);
    expect(pinyinRanges('买绿茶', 'lucha'), [(1, 3)]);
    // Latin in the title matches as itself; spaces can be skipped.
    expect(pinyinRanges('看 PPT 讲稿', 'pptjg'), [(2, 8)]);
    expect(pinyinRanges('周会 周报', 'zh'), [(0, 1), (3, 4)]);
    expect(pinyinRanges('写周报', 'zhou bao'), isEmpty);
    expect(pinyinRanges('写周报', ''), isEmpty);
  });
}
