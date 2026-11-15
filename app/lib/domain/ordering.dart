/// Manual order (拖动排序): tasks in a list, and the sections (分组) of a
/// list, keep the order the person drags them into.
///
/// Order is a number (`sortOrder`), smallest first. A move gives only the
/// moved item a new number, halfway between its new neighbours, so a drag
/// syncs as one changed row. When two neighbours get too close to fit
/// another number between them, the whole group is numbered afresh.
library;

/// Space left between items when numbering afresh, and past either end.
const orderStep = 1024.0;

/// Where to put item [movingId] so it lands at [index] of [ordered] (ids in
/// display order, smallest number first; it may already be among them, as
/// it is when dragging within a group). [orderOf] gives an item's current
/// number. Returns the new numbers: usually just the moved item's.
Map<String, double> planMove(
  List<String> ordered,
  String movingId,
  int index,
  double Function(String id) orderOf,
) {
  final from = ordered.indexOf(movingId);
  final rest = [...ordered]..remove(movingId);
  // The index counts the moved item where it was; take it out first.
  var at = from >= 0 && from < index ? index - 1 : index;
  at = at.clamp(0, rest.length);

  final before = at > 0 ? orderOf(rest[at - 1]) : null;
  final after = at < rest.length ? orderOf(rest[at]) : null;
  final double order;
  if (before == null && after == null) {
    return {movingId: from >= 0 ? orderOf(movingId) : 0};
  } else if (before == null) {
    order = after! - orderStep;
  } else if (after == null) {
    order = before + orderStep;
  } else {
    order = before + (after - before) / 2;
  }
  final fits = (before == null || order > before) && (after == null || order < after);
  if (fits) return {movingId: order};

  // No room: number everything again, keeping the first item's place.
  final all = [...rest]..insert(at, movingId);
  final start = orderOf(all.first == movingId && all.length > 1 ? all[1] : all.first);
  return {
    for (var i = 0; i < all.length; i++) all[i]: start + i * orderStep,
  };
}

/// Where to put the items [moving] (in the order they should end up) so
/// they land together at [index] of [ordered] (ids in display order; some
/// or all of [moving] may be among them, counted where they are). Returns
/// the new numbers, usually just the moved items'; empty when they're
/// already there, in that order.
Map<String, double> planMoveMany(
  List<String> ordered,
  List<String> moving,
  int index,
  double Function(String id) orderOf,
) {
  final movingSet = moving.toSet();
  final rest = [for (final id in ordered) if (!movingSet.contains(id)) id];
  var at = 0;
  for (var i = 0; i < index && i < ordered.length; i++) {
    if (!movingSet.contains(ordered[i])) at++;
  }
  final result = [...rest]..insertAll(at, moving);
  if (result.length == ordered.length &&
      Iterable<int>.generate(result.length).every((i) => result[i] == ordered[i])) {
    return const {};
  }

  final k = moving.length;
  final before = at > 0 ? orderOf(rest[at - 1]) : null;
  final after = at < rest.length ? orderOf(rest[at]) : null;
  final List<double> values;
  if (before == null && after == null) {
    values = [for (var i = 0; i < k; i++) i * orderStep];
  } else if (before == null) {
    values = [for (var i = 0; i < k; i++) after! - (k - i) * orderStep];
  } else if (after == null) {
    values = [for (var i = 0; i < k; i++) before + (i + 1) * orderStep];
  } else {
    final gap = (after - before) / (k + 1);
    values = [for (var i = 0; i < k; i++) before + (i + 1) * gap];
  }
  var fits = true;
  for (var i = 0; i < k; i++) {
    final low = i == 0 ? before : values[i - 1];
    if (low != null && !(values[i] > low)) fits = false;
  }
  if (after != null && !(values.last < after)) fits = false;
  if (fits) return {for (var i = 0; i < k; i++) moving[i]: values[i]};

  // No room: number everything again, keeping the first other item's place.
  final start = rest.isEmpty ? 0.0 : orderOf(rest.first) - (at == 0 ? k * orderStep : 0);
  return {for (var i = 0; i < result.length; i++) result[i]: start + i * orderStep};
}
