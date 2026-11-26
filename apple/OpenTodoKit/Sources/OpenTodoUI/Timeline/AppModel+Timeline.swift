// The timeline in the app: what a view's timeline shows, and how what the
// person does on it is written (TaskRepo). `TaskTimeline` is the view that
// puts these together with the `TimelineView` component.

import OpenTodoData
import OpenTodoDomain

extension AppModel {
    /// `view` as a timeline: a list's (the inbox's) lanes are its sections;
    /// elsewhere a lane per group of the view's grouping (list, tag,
    /// priority or none). Finished tasks only with 显示已完成.
    func timeline(for view: ViewRef) -> Timeline {
        let p = prefs(for: view)
        return buildViewTimeline(
            view, data.tasks, now: now, lists: listsById, filters: filterRules,
            sectionsByList: sectionsByList, grouping: p.timelineGroupingIn(view), sort: p.sortIn(view),
            showDone: settings.timelinePrefs.showDone
        )
    }

    /// Writes a change made on the timeline.
    func applyTimelineEdit(_ edit: TimelineEdit) async {
        await attempt {
            switch edit {
            case .place(let p):
                try await repo.placeOnTimeline(p.ids, days: p.days, day: p.day, target: p.target)
            case .unschedule(let ids):
                try await repo.dropInto(ids, .date(nil), [:])
            case let .setStart(id, date, duration):
                try await repo.setStart(id, date, duration)
            case let .setDuration(id, duration):
                try await repo.setDuration(id, duration)
            }
        }
    }

    /// A click on a task on the timeline: ⌘ and Shift pick (多选), a plain
    /// click opens it.
    func tapOnTimeline(_ id: String, modifiers: TapModifiers, order: [String]) {
        if let open = selection.tap(id, modifiers: modifiers, order: order, current: selectedTaskId) {
            self.open(taskId: open)
        }
    }

    /// What a task added by a click on `day` in a lane standing for
    /// `target` starts with: what the view gives new tasks, and the lane's
    /// list, section, tag or priority.
    func timelineNewTask(in view: ViewRef, on day: Day, lane target: GroupTarget?) -> QuickAddTarget {
        let n = laneNewTask(view, target, today, filterRules)
        return QuickAddTarget(listId: n.listId, sectionId: n.sectionId, date: day, tags: n.tags, priority: n.priority)
    }
}
