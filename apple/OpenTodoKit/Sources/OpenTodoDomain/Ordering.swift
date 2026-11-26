// Manual order (拖动排序), ported from `app/lib/domain/ordering.dart`: tasks
// in a list, and the sections (分组) of a list, keep the order the person
// drags them into.
//
// Order is a number (`sortOrder`), smallest first. A move gives only the
// moved item a new number, halfway between its new neighbours, so a drag
// syncs as one changed row. When two neighbours get too close to fit
// another number between them, the whole group is numbered afresh.

/// Space left between items when numbering afresh, and past either end.
public let orderStep = 1024.0

/// Where to put item `movingId` so it lands at `index` of `ordered` (ids in
/// display order, smallest number first; it may already be among them, as
/// it is when dragging within a group). `orderOf` gives an item's current
/// number. Returns the new numbers: usually just the moved item's.
public func planMove(
    _ ordered: [String],
    _ movingId: String,
    _ index: Int,
    _ orderOf: (String) -> Double
) -> [String: Double] {
    let from = ordered.firstIndex(of: movingId)
    var rest = ordered
    if let from { rest.remove(at: from) }
    // The index counts the moved item where it was; take it out first.
    var at = if let from, from < index { index - 1 } else { index }
    at = min(max(at, 0), rest.count)

    let before = at > 0 ? orderOf(rest[at - 1]) : nil
    let after = at < rest.count ? orderOf(rest[at]) : nil
    let order: Double
    switch (before, after) {
    case (nil, nil):
        return [movingId: from != nil ? orderOf(movingId) : 0]
    case let (nil, after?):
        order = after - orderStep
    case let (before?, nil):
        order = before + orderStep
    case let (before?, after?):
        order = before + (after - before) / 2
    }
    let fits = (before.map { order > $0 } ?? true) && (after.map { order < $0 } ?? true)
    if fits { return [movingId: order] }

    // No room: number everything again, keeping the first item's place.
    var all = rest
    all.insert(movingId, at: at)
    let start = orderOf(all[0] == movingId && all.count > 1 ? all[1] : all[0])
    var out: [String: Double] = [:]
    for (i, id) in all.enumerated() { out[id] = start + Double(i) * orderStep }
    return out
}

/// Where to put the items `moving` (in the order they should end up) so
/// they land together at `index` of `ordered` (ids in display order; some
/// or all of `moving` may be among them, counted where they are). Returns
/// the new numbers, usually just the moved items'; empty when they're
/// already there, in that order.
public func planMoveMany(
    _ ordered: [String],
    _ moving: [String],
    _ index: Int,
    _ orderOf: (String) -> Double
) -> [String: Double] {
    let movingSet = Set(moving)
    let rest = ordered.filter { !movingSet.contains($0) }
    var at = 0
    for i in 0..<max(0, min(index, ordered.count)) where !movingSet.contains(ordered[i]) {
        at += 1
    }
    var result = rest
    result.insert(contentsOf: moving, at: at)
    if result == ordered { return [:] }

    let k = moving.count
    let before = at > 0 ? orderOf(rest[at - 1]) : nil
    let after = at < rest.count ? orderOf(rest[at]) : nil
    let values: [Double]
    switch (before, after) {
    case (nil, nil):
        values = (0..<k).map { Double($0) * orderStep }
    case let (nil, after?):
        values = (0..<k).map { after - Double(k - $0) * orderStep }
    case let (before?, nil):
        values = (0..<k).map { before + Double($0 + 1) * orderStep }
    case let (before?, after?):
        let gap = (after - before) / Double(k + 1)
        values = (0..<k).map { before + Double($0 + 1) * gap }
    }
    var fits = true
    for i in 0..<k {
        let low = i == 0 ? before : values[i - 1]
        if let low, !(values[i] > low) { fits = false }
    }
    if let after, let last = values.last, !(last < after) { fits = false }
    if fits {
        var out: [String: Double] = [:]
        for i in 0..<k { out[moving[i]] = values[i] }
        return out
    }

    // No room: number everything again, keeping the first other item's place.
    let start = rest.isEmpty ? 0.0 : orderOf(rest[0]) - (at == 0 ? Double(k) * orderStep : 0)
    var out: [String: Double] = [:]
    for (i, id) in result.enumerated() { out[id] = start + Double(i) * orderStep }
    return out
}
