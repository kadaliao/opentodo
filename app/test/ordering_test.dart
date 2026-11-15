import 'package:flutter_test/flutter_test.dart';
import 'package:opentodo/domain/ordering.dart';

void main() {
  Map<String, double> orders(Map<String, double> m) => m;

  test('a move gives only the moved item a number between its neighbours', () {
    final o = orders({'a': 10, 'b': 20, 'c': 30});
    double of(String id) => o[id]!;
    // c to the top.
    expect(planMove(['a', 'b', 'c'], 'c', 0, of), {'c': 10 - orderStep});
    // a between b and c (the index counts a where it was).
    expect(planMove(['a', 'b', 'c'], 'a', 2, of), {'a': 25});
    // a to the end.
    expect(planMove(['a', 'b', 'c'], 'a', 3, of), {'a': 30 + orderStep});
    // Dropped where it already is.
    expect(planMove(['a', 'b', 'c'], 'b', 1, of), {'b': 20});
  });

  test('an item from elsewhere goes in at the index', () {
    final o = orders({'a': 10, 'b': 20, 'x': 99});
    double of(String id) => o[id]!;
    expect(planMove(['a', 'b'], 'x', 1, of), {'x': 15});
    expect(planMove(['a', 'b'], 'x', 0, of), {'x': 10 - orderStep});
    expect(planMove(['a', 'b'], 'x', 9, of), {'x': 20 + orderStep});
    expect(planMove([], 'x', 0, of), {'x': 0});
  });

  test('no room between neighbours: the group is numbered again', () {
    final o = orders({'a': 5, 'b': 5, 'c': 5, 'x': 0});
    double of(String id) => o[id]!;
    expect(planMove(['a', 'b', 'c'], 'x', 1, of), {
      'a': 5,
      'x': 5 + orderStep,
      'b': 5 + 2 * orderStep,
      'c': 5 + 3 * orderStep,
    });
    // Halving the same gap again and again ends in a renumbering, never in
    // a wrong order.
    final p = {'a': 0.0, 'b': 1.0, 'x': 0.0};
    var list = ['a', 'b'];
    for (var i = 0; i < 80; i++) {
      final id = 'n$i';
      p[id] = 0;
      final moved = planMove(list, id, 1, (k) => p[k]!);
      p.addAll(moved);
      list = [...list]..insert(1, id);
      final sorted = [...list]..sort((x, y) => p[x]!.compareTo(p[y]!));
      expect(sorted, list);
    }
  });

  group('several at once', () {
    final o = {'a': 10.0, 'b': 20.0, 'c': 30.0, 'd': 40.0};
    double of(String id) => o[id]!;

    test('land together between their new neighbours, in the order given', () {
      // a and c moved to after d (index counts them where they are).
      expect(planMoveMany(['a', 'b', 'c', 'd'], ['a', 'c'], 4, of), {'a': 40 + orderStep, 'c': 40 + 2 * orderStep});
      // To the top.
      expect(planMoveMany(['a', 'b', 'c', 'd'], ['c', 'd'], 0, of), {'c': 10 - 2 * orderStep, 'd': 10 - orderStep});
      // Between a and b: thirds of the gap.
      final m = planMoveMany(['a', 'b', 'c', 'd'], ['d', 'c'], 1, of);
      expect(m.keys, ['d', 'c']);
      expect(m['d']! > 10 && m['d']! < m['c']! && m['c']! < 20, isTrue);
      // Coming from elsewhere.
      expect(planMoveMany(['a', 'b'], ['x', 'y'], 1, of), {'x': 10 + 10 / 3, 'y': 10 + 20 / 3});
      expect(planMoveMany([], ['x', 'y'], 0, of), {'x': 0, 'y': orderStep});
    });

    test('already there in that order: nothing to do', () {
      expect(planMoveMany(['a', 'b', 'c', 'd'], ['b', 'c'], 1, of), isEmpty);
      expect(planMoveMany(['a', 'b', 'c', 'd'], ['b', 'c'], 3, of), isEmpty);
      expect(planMoveMany(['a', 'b', 'c', 'd'], ['c', 'b'], 1, of), isNotEmpty);
    });

    test('no room: everything numbered again, in the new order', () {
      final tight = {'a': 1.0, 'b': 1.0 + 2.220446049250313e-16, 'c': 3.0}; // b one step above a
      final m = planMoveMany(['a', 'b', 'c'], ['c', 'x'], 1, (id) => tight[id] ?? 0);
      final p = {...tight, ...m};
      final sorted = [...p.keys]..sort((x, y) => p[x]!.compareTo(p[y]!));
      expect(sorted, ['a', 'c', 'x', 'b']);
      expect(m['a'], 1.0);
    });
  });
}
