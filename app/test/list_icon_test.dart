import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/list_icon.dart';

void main() {
  test('a symbol icon (the Swift version\'s) shows as none here', () {
    expect(listEmoji('💼'), '💼');
    expect(listEmoji('AI'), 'AI');
    expect(listEmoji('sf:briefcase'), isNull);
    expect(listEmoji(''), isNull);
    expect(listEmoji(null), isNull);
  });
}
