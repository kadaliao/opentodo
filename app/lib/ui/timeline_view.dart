import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderProxyBox, ViewportOffset;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/holidays.dart';
import '../domain/timeline.dart';
import '../domain/views.dart';
import '../state/providers.dart';
import '../state/selection.dart';
import '../state/timeline_providers.dart';
import 'calendar/calendar_screen.dart' show showNewTaskDialog;
import 'task_actions.dart';
import 'task_drag.dart';
import 'task_tile.dart' show PriorityCheckbox;
import 'theme.dart' show Breakpoints;

const _rowHeight = 32.0;
const _barHeight = 26.0;
const _laneHeaderHeight = 30.0;
const _headerHeight = 40.0;

/// Room around a bar inside its days.
const _barInset = 2.0;

/// A bar narrower than this has its title beside it instead of inside.
const _titleInside = 88.0;

/// How far the timeline scrolls each way from where it opened.
const _reachDays = 3650;

double _dayWidth(TimelineScale s) => switch (s) {
      TimelineScale.day => 96,
      TimelineScale.week => 36,
      TimelineScale.month => 14,
    };

/// Days before today on screen when the timeline goes to today.
int _leadDays(TimelineScale s) => switch (s) {
      TimelineScale.day => 1,
      TimelineScale.week => 3,
      TimelineScale.month => 7,
    };

/// A list as a timeline (时间线): its dated tasks as bars along the days,
/// a lane per section, and its undated ones beside it (无日期) to drag on.
class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key, required this.listId, required this.onOpenTask});

  final String listId;
  final ValueChanged<String> onOpenTask;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  /// The day at the left edge when scrolled to 0.
  final DateTime _origin = dateOnly(DateTime.now());
  late final ScrollController _h;
  final _v = ScrollController();

  /// Lanes the person folded, by section id ('' for 未分组).
  final _collapsed = <String>{};

  /// The days a dragged task would cover if let go now, lit up along the
  /// top.
  final _dropDays = ValueNotifier<_Days?>(null);

  @override
  void initState() {
    super.initState();
    _h = ScrollController(initialScrollOffset: _homeOffset(ref.read(timelinePrefsProvider).scale));
    ref.listenManual(timelinePrefsProvider.select((p) => p.scale), (from, to) {
      if (from == null || from == to || !_h.hasClients) return;
      // The same day stays at the left edge; at today it stays at today.
      final left = _h.offset / _dayWidth(from);
      final home = _homeOffset(from) / _dayWidth(from);
      _h.jumpTo((left - home).abs() < 0.01 ? _homeOffset(to) : left * _dayWidth(to));
    });
  }

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    _dropDays.dispose();
    super.dispose();
  }

  /// Where today shows with a day or few before it.
  double _homeOffset(TimelineScale scale) =>
      (daysBetween(_origin, DateTime.now()) - _leadDays(scale)) * _dayWidth(scale);

  void _goTo(double offset) => _h.animateTo(offset, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);

  void _page(int direction, TimelineScale scale) {
    if (!_h.hasClients) return;
    final dw = _dayWidth(scale);
    final days = math.max((_h.position.viewportDimension / dw).floor() - 1, 1);
    _goTo(((_h.offset / dw).round() + direction * days) * dw);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(timelinePrefsProvider);
    final scale = prefs.scale;
    final listId = widget.listId;
    final sort = (ref.watch(viewPrefsProvider)[listId] ?? const ViewPrefs()).sortIn(ListViewRef(listId))!;
    final sections = ref.watch(sectionsByListProvider)[listId] ?? const <ListSection>[];
    final timeline = buildTimeline(listId, ref.watch(tasksProvider).value ?? const [], sections,
        sort: sort, showDone: prefs.showDone);
    final rows = [for (final l in timeline.lanes) packRows(l.bars, minDays: scale.minDays)];
    final undated = timeline.undatedTasks.toList();
    final touch = dragsOnLongPress(context);
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.twoPane;
    final trayOpen = prefs.trayOpen ?? !narrow;
    final now = ref.watch(clockProvider);

    // Clicks with ⌘ / Shift pick tasks: the undated ones, then lane by lane.
    final order = [
      for (final t in undated) t.id,
      for (final l in timeline.lanes) for (final b in l.bars) b.task.id,
    ];
    void open(String id) => tapTask(ref, id, order, widget.onOpenTask, touch: touch);
    final selection = ref.watch(taskSelectionProvider);
    final picked = [
      if (selection.active)
        for (final t in [...undated, for (final l in timeline.lanes) for (final b in l.bars) b.task])
          if (selection.ids.contains(t.id) && isOpen(t)) t,
    ];

    final tray = _UndatedTray(
      groups: timeline.undated,
      titled: sections.isNotEmpty,
      picked: picked,
      onOpen: open,
    );
    final canvas = Scrollable(
      axisDirection: AxisDirection.right,
      controller: _h,
      viewportBuilder: (context, offset) => _EndlessViewport(
        offset: offset,
        reach: _reachDays * _dayWidth(scale),
        child: LayoutBuilder(
          builder: (context, c) => AnimatedBuilder(
            animation: offset,
            builder: (context, _) => _canvas(
              context,
              _Geometry(_origin, scale, offset.pixels, c.maxWidth),
              timeline: timeline,
              rows: rows,
              picked: picked,
              open: open,
              now: now,
              narrow: narrow,
              height: c.maxHeight,
            ),
          ),
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Toolbar(
        controller: _h,
        origin: _origin,
        prefs: prefs,
        undatedCount: undated.length,
        trayOpen: trayOpen,
        onToday: () => _goTo(_homeOffset(scale)),
        onPage: (d) => _page(d, scale),
        narrow: narrow,
      ),
      Expanded(
        child: narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: canvas),
                if (trayOpen) ...[const Divider(height: 1), SizedBox(height: 132, child: tray)],
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (trayOpen) ...[SizedBox(width: 220, child: tray), const VerticalDivider(width: 1)],
                Expanded(child: canvas),
              ]),
      ),
    ]);
  }

  /// What shows at scroll offset [g.pixels]: the days along the top, and
  /// the lanes under them.
  Widget _canvas(
    BuildContext context,
    _Geometry g, {
    required Timeline timeline,
    required List<List<List<TimelineBar>>> rows,
    required List<Task> picked,
    required ValueChanged<String> open,
    required DateTime now,
    required bool narrow,
    required double height,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(now);
    final showHeaders = timeline.lanes.length > 1 || timeline.lanes.any((l) => l.section != null);
    // Where now is: through today's column on the time of day.
    final nowX = g.x(today) +
        (g.scale == TimelineScale.month ? g.dayWidth / 2 : g.dayWidth * (now.hour * 60 + now.minute) / minutesPerDay);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder(
        valueListenable: _dropDays,
        builder: (context, drop, _) => _DayHeader(geometry: g, today: today, drop: drop),
      ),
      const Divider(height: 1),
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                g,
                tint: scheme.onSurface.withValues(alpha: 0.035),
                line: scheme.outlineVariant.withValues(alpha: 0.45),
                strong: scheme.outlineVariant,
              ),
            ),
          ),
          ListView(
            controller: _v,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final (i, lane) in timeline.lanes.indexed)
                _Lane(
                  key: ValueKey('lane-${lane.section?.id ?? ''}'),
                  listId: widget.listId,
                  lane: lane,
                  rows: rows[i],
                  geometry: g,
                  picked: picked,
                  onOpen: open,
                  showHeader: showHeaders,
                  dropDays: _dropDays,
                  collapsed: _collapsed.contains(lane.section?.id ?? ''),
                  onToggle: () => setState(() {
                    final id = lane.section?.id ?? '';
                    if (!_collapsed.remove(id)) _collapsed.add(id);
                  }),
                  // A lone lane fills the screen, so a click anywhere adds.
                  minHeight: timeline.lanes.length == 1
                      ? height - _headerHeight - 1 - 24 - (showHeaders ? _laneHeaderHeight : 0)
                      : 0,
                  onNewTask: (day) => showNewTaskDialog(
                    context,
                    date: day,
                    sheet: narrow,
                    listId: widget.listId,
                    sectionId: lane.section?.id,
                  ),
                ),
            ],
          ),
          if (nowX >= 0 && nowX <= g.width)
            Positioned(
              left: nowX - 0.75,
              top: 0,
              bottom: 0,
              width: 1.5,
              child: IgnorePointer(child: ColoredBox(color: scheme.error.withValues(alpha: 0.8))),
            ),
        ]),
      ),
    ]);
  }
}

/// Where the days are on screen at one scroll offset.
class _Geometry {
  _Geometry(this.origin, this.scale, this.pixels, this.width) : dayWidth = _dayWidth(scale);

  final DateTime origin;
  final TimelineScale scale;
  final double pixels, width, dayWidth;

  /// Where [day] starts, from the left edge of the timeline.
  double x(DateTime day) => daysBetween(origin, day) * dayWidth - pixels;

  /// The day at [x] from the left edge.
  DateTime dayAt(double x) => addDays(origin, ((x + pixels) / dayWidth).floor());

  DateTime get firstDay => dayAt(0);
  DateTime get lastDay => dayAt(width - 0.01);
}

/// Lays out its child to fill it and tells the scroll position it can go a
/// long way either side ([reach]), so the timeline seems endless.
class _EndlessViewport extends SingleChildRenderObjectWidget {
  const _EndlessViewport({required this.offset, required this.reach, super.child});

  final ViewportOffset offset;
  final double reach;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEndlessViewport(offset, reach);

  @override
  void updateRenderObject(BuildContext context, _RenderEndlessViewport renderObject) {
    renderObject
      ..offset = offset
      ..reach = reach;
  }
}

class _RenderEndlessViewport extends RenderProxyBox {
  _RenderEndlessViewport(this._offset, this._reach);

  ViewportOffset _offset;
  set offset(ViewportOffset value) {
    if (value == _offset) return;
    _offset = value;
    markNeedsLayout();
  }

  double _reach;
  set reach(double value) {
    if (value == _reach) return;
    _reach = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    _offset.applyViewportDimension(size.width);
    _offset.applyContentDimensions(-_reach, _reach);
    child?.layout(BoxConstraints.tight(size));
  }
}

/// The bar over the timeline: the month on screen, 无日期, paging, today,
/// and the scale.
class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.controller,
    required this.origin,
    required this.prefs,
    required this.undatedCount,
    required this.trayOpen,
    required this.onToday,
    required this.onPage,
    required this.narrow,
  });

  /// A phone: swiping pages, so no arrows.
  final bool narrow;
  final ScrollController controller;
  final DateTime origin;
  final TimelinePrefs prefs;
  final int undatedCount;
  final bool trayOpen;
  final VoidCallback onToday;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(timelinePrefsProvider.notifier);
    const check = Icon(Icons.check, size: 18);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(children: [
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final offset = controller.hasClients ? controller.offset : controller.initialScrollOffset;
              final day = addDays(origin, (offset / _dayWidth(prefs.scale) + 0.5).floor());
              return Text(timelineMonthLabel(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant));
            },
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: trayOpen ? scheme.primary : scheme.onSurfaceVariant,
            backgroundColor: trayOpen ? scheme.primary.withValues(alpha: 0.08) : null,
          ),
          icon: const Icon(Icons.event_busy_outlined, size: 16),
          label: Text('无日期 $undatedCount'),
          onPressed: () => notifier.set(prefs.copyWith(trayOpen: !trayOpen)),
        ),
        const SizedBox(width: 4),
        if (!narrow)
          IconButton(
            tooltip: '往前',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onPage(-1),
          ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onToday,
          child: const Text('今天'),
        ),
        if (!narrow)
          IconButton(
            tooltip: '往后',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onPage(1),
          ),
        MenuAnchor(
          menuChildren: [
            for (final s in TimelineScale.values)
              MenuItemButton(
                trailingIcon: s == prefs.scale ? check : null,
                onPressed: () => notifier.set(prefs.copyWith(scale: s)),
                child: Text('按${s.label}'),
              ),
            const Divider(height: 8),
            MenuItemButton(
              trailingIcon: prefs.showDone ? check : null,
              onPressed: () => notifier.set(prefs.copyWith(showDone: !prefs.showDone)),
              child: const Text('显示已完成'),
            ),
          ],
          builder: (context, controller, _) => TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(prefs.scale.label),
              const Icon(Icons.arrow_drop_down, size: 18),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The days along the top. A mouse can drag it to scroll.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.geometry, required this.today, this.drop});

  final _Geometry geometry;
  final DateTime today;

  /// The days a dragged task would land on.
  final _Days? drop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = geometry;
    final labels = <Widget>[
      if (drop case final d?)
        Positioned(
          left: g.x(d.start) + 1,
          width: d.days * g.dayWidth - 2,
          top: 2,
          bottom: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
    ];
    if (g.scale == TimelineScale.month) {
      // Each month's name where it starts (the one on screen at the left
      // edge until the next pushes it out), and every Monday's date.
      var month = DateTime(g.firstDay.year, g.firstDay.month);
      while (!month.isAfter(g.lastDay)) {
        final next = DateTime(month.year, month.month + 1);
        final left = math.max(g.x(month), 0.0);
        final room = g.x(next) - left;
        if (room > 24) {
          labels.add(Positioned(
            left: left + 4,
            top: 3,
            width: room - 4,
            child: Text(
              month.month == 1 ? '${month.year}年1月' : '${month.month}月',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ));
        }
        month = next;
      }
      for (var d = startOfWeek(g.firstDay); !d.isAfter(g.lastDay); d = addDays(d, 7)) {
        labels.add(Positioned(
          left: g.x(d) + 2,
          top: 21,
          child: Text('${d.day}', style: TextStyle(fontSize: 10, color: scheme.outline)),
        ));
      }
      if (!today.isBefore(g.firstDay) && !today.isAfter(g.lastDay)) {
        labels.add(Positioned(
          left: g.x(today) + g.dayWidth / 2 - 3,
          top: 33,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
          ),
        ));
      }
    } else {
      final wide = g.scale == TimelineScale.day;
      for (var d = g.firstDay; !d.isAfter(g.lastDay); d = addDays(d, 1)) {
        final isToday = d == today;
        final off = holidayOn(d)?.off ?? d.weekday >= DateTime.saturday;
        final color = isToday ? scheme.onError : (off ? scheme.outline : scheme.onSurface);
        final number = d.day == 1 ? '${d.month}月' : '${d.day}';
        labels.add(Positioned(
          left: g.x(d),
          width: g.dayWidth,
          top: 0,
          bottom: 0,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              wide ? weekdayName(d) : weekdayName(d).substring(1),
              style: TextStyle(fontSize: 10, height: 1.2, color: isToday ? scheme.error : scheme.outline),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: isToday
                  ? BoxDecoration(color: scheme.error, borderRadius: BorderRadius.circular(9))
                  : null,
              child: Text(
                number,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: isToday || d.day == 1 ? FontWeight.w600 : FontWeight.w500,
                  color: d.day == 1 && !isToday ? scheme.primary : color,
                ),
              ),
            ),
          ]),
        ));
      }
    }
    return GestureDetector(
      // Touch and trackpads scroll anyway; a mouse drags the dates.
      supportedDevices: const {PointerDeviceKind.mouse},
      onHorizontalDragUpdate: (d) {
        final p = Scrollable.of(context).position;
        p.jumpTo(p.pixels - d.delta.dx);
      },
      child: SizedBox(
        height: _headerHeight,
        child: ClipRect(child: Stack(children: labels)),
      ),
    );
  }
}

/// Days off tinted (unless they're too narrow to tell apart), lines
/// between days (between weeks and months when they're narrow).
class _GridPainter extends CustomPainter {
  _GridPainter(this.g, {required this.tint, required this.line, required this.strong});

  final _Geometry g;
  final Color tint, line, strong;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = tint;
    final thin = Paint()
      ..color = line
      ..strokeWidth = 1;
    final bold = Paint()
      ..color = strong
      ..strokeWidth = 1;
    for (var d = g.firstDay; !d.isAfter(g.lastDay); d = addDays(d, 1)) {
      final x = g.x(d);
      if (g.scale != TimelineScale.month && (holidayOn(d)?.off ?? d.weekday >= DateTime.saturday)) {
        canvas.drawRect(Rect.fromLTWH(x, 0, g.dayWidth, size.height), fill);
      }
      final Paint? paint = switch (g.scale) {
        TimelineScale.day => thin,
        TimelineScale.week => d.day == 1 ? bold : (d.weekday == DateTime.monday ? thin : null),
        TimelineScale.month => d.day == 1 ? bold : (d.weekday == DateTime.monday ? thin : null),
      };
      if (paint != null) canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.g.pixels != g.pixels ||
      old.g.width != g.width ||
      old.g.scale != g.scale ||
      old.tint != tint ||
      old.line != line ||
      old.strong != strong;
}

/// One lane: a section's name across the top (unless the list has none),
/// and its tasks in rows. Takes tasks dragged onto it: they move to the
/// day they're let go on and into this section.
class _Lane extends ConsumerStatefulWidget {
  const _Lane({
    super.key,
    required this.listId,
    required this.lane,
    required this.rows,
    required this.geometry,
    required this.picked,
    required this.onOpen,
    required this.showHeader,
    required this.collapsed,
    required this.onToggle,
    required this.minHeight,
    required this.onNewTask,
    required this.dropDays,
  });

  /// Shared by the lanes: the days a dragged task would land on.
  final ValueNotifier<_Days?> dropDays;
  final String listId;
  final TimelineLane lane;
  final List<List<TimelineBar>> rows;
  final _Geometry geometry;

  /// The picked tasks of the whole timeline, which are dragged together.
  final List<Task> picked;
  final ValueChanged<String> onOpen;
  final bool showHeader;
  final bool collapsed;
  final VoidCallback onToggle;
  final double minHeight;
  final ValueChanged<DateTime> onNewTask;

  @override
  ConsumerState<_Lane> createState() => _LaneState();
}

class _LaneState extends ConsumerState<_Lane> {
  /// Where a task being dragged over would go.
  _Days? _drop;

  /// The day under the mouse, where a click adds a task.
  DateTime? _hover;

  /// A bar whose right edge is being dragged, and the last day it reaches.
  ({String id, DateTime last})? _resize;

  _Geometry get g => widget.geometry;

  bool _takes(Task t) => isOpen(t) && t.listId == widget.listId;

  /// The day a dragged task would start on: the part of its bar the pointer
  /// holds stays under the pointer; a task without a date goes on the day
  /// under the pointer.
  _Days _dropAt(DragTargetDetails<DraggedTasks> d) {
    final box = context.findRenderObject()! as RenderBox;
    final grab = taskDragGrab ?? Offset.zero;
    final under = g.dayAt(box.globalToLocal(d.offset + grab).dx);
    final lead = d.data.lead;
    if (lead.dueDate == null) return (start: under, days: 1);
    final bar = TimelineBar(lead);
    final held = ((grab.dx + _barInset) / g.dayWidth).floor().clamp(0, bar.days - 1);
    return (start: addDays(under, -held), days: bar.days);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lane = widget.lane;
    final touch = dragsOnLongPress(context);
    final count = lane.bars.where((b) => !b.done).length;
    final height = math.max((math.max(widget.rows.length, 1) + 1) * _rowHeight, widget.minHeight);
    // Bars that show (with room for a title beside them), and any being
    // dragged, which must stay built until it's let go.
    final from = addDays(g.firstDay, -g.scale.minDays), to = g.lastDay;

    final body = <Widget>[
      Positioned.fill(
        child: MouseRegion(
          onHover: touch ? null : (e) {
            final day = g.dayAt(e.localPosition.dx);
            if (day != _hover) setState(() => _hover = day);
          },
          onExit: (_) {
            if (mounted && _hover != null) setState(() => _hover = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onNewTask(g.dayAt(d.localPosition.dx)),
          ),
        ),
      ),
      // Always there, so the bars keep their places among the children.
      _Highlight(
        key: const ValueKey('hover'),
        left: _hover == null || _drop != null ? null : g.x(_hover!),
        width: g.dayWidth,
        color: scheme.primary.withValues(alpha: 0.05),
        child: g.dayWidth >= 30 ? Icon(Icons.add, size: 16, color: scheme.primary) : null,
      ),
    ];
    for (final (row, bars) in widget.rows.indexed) {
      for (final b in bars) {
        if (!b.overlaps(from, to) && !isTaskDragged(b.task.id)) continue;
        final resizing = _resize?.id == b.task.id ? _resize!.last : null;
        final days = resizing == null ? b.days : daysBetween(b.start, resizing) + 1;
        final left = g.x(b.start) + _barInset;
        final width = days * g.dayWidth - 2 * _barInset;
        final top = row * _rowHeight + (_rowHeight - _barHeight) / 2 + 4;
        final open = !b.done;
        Widget bar = _Bar(task: b.task, width: width, onOpen: widget.onOpen);
        if (open) bar = TaskDraggable(task: b.task, picked: widget.picked, width: width, child: bar);
        body.add(Positioned(
          key: ValueKey('bar-${b.task.id}'),
          left: left,
          top: top,
          width: width,
          height: _barHeight,
          child: bar,
        ));
        // While its right edge is dragged: where it will end, beside it.
        if (resizing != null) {
          body.add(Positioned(
            key: const ValueKey('resize-label'),
            left: left + width + 4,
            top: top + 4,
            child: IgnorePointer(child: _Pill('到${_dayLabel(resizing)}')),
          ));
        } else if (width < _titleInside) {
          // Too narrow for its title: the title beside it.
          final room = math.max(g.scale.minDays, days) * g.dayWidth - width - 3 * _barInset;
          body.add(Positioned(
            key: ValueKey('title-${b.task.id}'),
            left: left + width + 4,
            top: top,
            width: room,
            height: _barHeight,
            child: GestureDetector(
              onTap: () => widget.onOpen(b.task.id),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  b.task.title.isEmpty ? '无标题' : b.task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: b.done ? scheme.outline : scheme.onSurface,
                    decoration: b.done ? TextDecoration.lineThrough : null,
                    decorationColor: scheme.outline,
                  ),
                ),
              ),
            ),
          ));
        }
        // The right edge sets the last day (with a mouse).
        if (open && !touch) {
          body.add(Positioned(
            key: ValueKey('edge-${b.task.id}'),
            left: left + width - 5,
            top: top,
            width: 8,
            height: _barHeight,
            child: _ResizeEdge(
              dayWidth: g.dayWidth,
              onStart: () => setState(() => _resize = (id: b.task.id, last: b.last)),
              onUpdate: (dx) {
                final last = addDays(b.last, (dx / g.dayWidth).round());
                final clamped = last.isBefore(b.start) ? b.start : last;
                if (_resize?.last != clamped) setState(() => _resize = (id: b.task.id, last: clamped));
              },
              onEnd: () {
                final last = _resize?.last;
                setState(() => _resize = null);
                if (last == null || last == b.last) return;
                ref.read(repoProvider).setDuration(b.task.id, resizedDuration(b.task, last));
              },
            ),
          ));
        }
      }
    }

    // Where a dragged task would land, over the bars (the days light up
    // along the top too).
    body.add(_Highlight(
      key: const ValueKey('drop'),
      left: _drop == null ? null : g.x(_drop!.start),
      width: (_drop?.days ?? 1) * g.dayWidth,
      color: scheme.primary.withValues(alpha: 0.1),
      border: scheme.primary,
    ));

    return DragTarget<DraggedTasks>(
      onWillAcceptWithDetails: (d) => d.data.all.any(_takes),
      onMove: (d) {
        final at = _dropAt(d);
        widget.dropDays.value = at;
        if (at != _drop) setState(() => _drop = at);
      },
      onLeave: (_) {
        widget.dropDays.value = null;
        setState(() => _drop = null);
      },
      onAcceptWithDetails: (d) {
        final at = _dropAt(d);
        widget.dropDays.value = null;
        setState(() => _drop = null);
        final lead = d.data.lead;
        final ids = [for (final t in d.data.all) if (_takes(t)) t.id];
        ref.read(repoProvider).placeOnTimeline(
              ids,
              days: lead.dueDate == null ? 0 : daysBetween(parseDateKey(lead.dueDate!), at.start),
              day: at.start,
              sectionId: lane.section?.id,
            );
      },
      builder: (context, _, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.showHeader)
          _LaneHeader(
            title: lane.title,
            count: count,
            collapsed: widget.collapsed,
            onToggle: widget.onToggle,
          ),
        if (!widget.collapsed)
          SizedBox(
            height: height,
            child: Stack(clipBehavior: Clip.hardEdge, children: body),
          ),
      ]),
    );
  }
}

/// Days from [start], [days] of them.
typedef _Days = ({DateTime start, int days});

String _dayLabel(DateTime d) => '${d.month}月${d.day}日';

/// A date said while a bar's edge is dragged.
class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4)),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onPrimary),
      ),
    );
  }
}

/// A tinted column over a lane (the day under the mouse, or where a
/// dragged task would land); nothing when [left] is null.
class _Highlight extends StatelessWidget {
  const _Highlight({super.key, required this.left, required this.width, required this.color, this.border, this.child});

  final double? left;
  final double width;
  final Color color;
  final Color? border;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Positioned(
        left: left ?? 0,
        width: left == null ? 0 : width,
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: left == null
              ? const SizedBox.shrink()
              : Container(
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
                  decoration: BoxDecoration(
                    color: color,
                    border: border == null ? null : Border.all(color: border!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: child,
                ),
        ),
      );
}

class _LaneHeader extends StatelessWidget {
  const _LaneHeader({required this.title, required this.count, required this.collapsed, required this.onToggle});

  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onToggle,
        child: SizedBox(
          height: _laneHeaderHeight,
          child: Row(children: [
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 12, color: scheme.outline)),
          ]),
        ),
      ),
    );
  }
}

/// A task on the timeline: checkbox and title (when there's room) over the
/// days it covers.
class _Bar extends ConsumerWidget {
  const _Bar({required this.task, required this.width, required this.onOpen});

  final Task task;
  final double width;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final picking = ref.watch(taskSelectionProvider);
    final selected = picking.active ? picking.ids.contains(task.id) : ref.watch(selectedTaskProvider) == task.id;
    final done = task.status != TaskStatus.open;
    final touch = dragsOnLongPress(context);
    final (bg, fg) = done
        ? (scheme.surfaceContainerHighest, scheme.outline)
        : selected
            ? (scheme.secondaryContainer, scheme.onSecondaryContainer)
            : (scheme.primaryContainer, scheme.onPrimaryContainer);
    final overdue = isOverdue(task, ref.watch(clockProvider));
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: selected ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(task.id),
        onSecondaryTapDown: (d) => showTaskMenu(context, ref, task, d.globalPosition),
        // On a touch screen a long press drags; the menu comes from letting
        // go without moving (TaskDraggable).
        onLongPress: touch && !done
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                showTaskMenu(context, ref, task, box.localToGlobal(box.size.center(Offset.zero)));
              },
        child: Container(
          height: _barHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            if (width >= 20)
              PriorityCheckbox(
                checked: done,
                priority: task.priority,
                size: 12,
                onChanged: (v) => setTaskDone(context, ref, task, v),
              ),
            if (width >= _titleInside) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.title.isEmpty ? '无标题' : task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: fg,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: fg,
                  ),
                ),
              ),
              if (task.dueTime != null && width >= 120)
                Text(
                  timeLabel(task.dueTime!),
                  style: TextStyle(fontSize: 10, color: overdue ? scheme.error : fg.withValues(alpha: 0.8)),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The right edge of a bar, dragged with a mouse to make it end on another
/// day; [onUpdate] gets how far it has gone.
class _ResizeEdge extends StatefulWidget {
  const _ResizeEdge({required this.dayWidth, required this.onStart, required this.onUpdate, required this.onEnd});

  final double dayWidth;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  State<_ResizeEdge> createState() => _ResizeEdgeState();
}

class _ResizeEdgeState extends State<_ResizeEdge> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            _dx = 0;
            widget.onStart();
          },
          onHorizontalDragUpdate: (d) {
            _dx += d.delta.dx;
            widget.onUpdate(_dx);
          },
          onHorizontalDragEnd: (_) => widget.onEnd(),
          onHorizontalDragCancel: widget.onEnd,
        ),
      );
}

/// The list's open tasks without a date (无日期), beside the timeline: drag
/// one onto a day to give it that date, or a task from the timeline here to
/// take its date away.
class _UndatedTray extends ConsumerWidget {
  const _UndatedTray({
    required this.groups,
    required this.titled,
    required this.picked,
    required this.onOpen,
  });

  final List<ListGroup> groups;

  /// The list has sections: show which each task is in.
  final bool titled;
  final List<Task> picked;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final count = groups.fold(0, (n, g) => n + g.tasks.length);
    return TaskDropArea(
      group: const GroupDrop(DateTarget(null)),
      index: 0,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            const Text('无日期', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 12, color: scheme.outline)),
            const Spacer(),
            if (count > 0)
              Text('拖到日期上', style: TextStyle(fontSize: 11, color: scheme.outline)),
          ]),
        ),
        Expanded(
          child: count == 0
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '没有无日期的任务\n把时间线上的任务拖到这里，可以去掉日期',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, height: 1.5, color: scheme.outline),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    for (final g in groups) ...[
                      if (titled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                          child: Text(g.title, style: TextStyle(fontSize: 11, color: scheme.outline)),
                        ),
                      for (final t in g.tasks)
                        Padding(
                          key: ValueKey(t.id),
                          padding: const EdgeInsets.only(bottom: 4),
                          child: TaskDraggable(
                            task: t,
                            picked: picked,
                            child: _TrayRow(task: t, onOpen: onOpen),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}

class _TrayRow extends ConsumerWidget {
  const _TrayRow({required this.task, required this.onOpen});

  final Task task;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final picking = ref.watch(taskSelectionProvider);
    final selected = picking.active ? picking.ids.contains(task.id) : ref.watch(selectedTaskProvider) == task.id;
    final touch = dragsOnLongPress(context);
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onOpen(task.id),
        onSecondaryTapDown: (d) => showTaskMenu(context, ref, task, d.globalPosition),
        onLongPress: touch
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                showTaskMenu(context, ref, task, box.localToGlobal(box.size.center(Offset.zero)));
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(children: [
            PriorityCheckbox(
              checked: false,
              priority: task.priority,
              size: 14,
              onChanged: (v) => setTaskDone(context, ref, task, v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.title.isEmpty ? '无标题' : task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: task.title.isEmpty ? scheme.outline : scheme.onSurface),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
