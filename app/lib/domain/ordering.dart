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
