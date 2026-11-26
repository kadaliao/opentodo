// What comes out of the timeline component (`TimelineView`). Its options
// are the data layer's `TimelinePrefs` (`LocalSettings.timelinePrefs`).

import Foundation
import OpenTodoDomain

/// Tasks dragged onto a lane: `TaskRepo.placeOnTimeline(ids, days:, day:,
/// target:)`. Dated tasks move `days` days (keeping their times and spans),
/// undated ones go on `day`, and all take on what the lane stands for
/// (`target`: a section, list, tag or priority; nil for none).
public struct TimelinePlacement: Sendable, Hashable {
    public var ids: [String]
    public var days: Int
    public var day: Day
    public var target: GroupTarget?

    public init(ids: [String], days: Int, day: Day, target: GroupTarget?) {
        self.ids = ids
        self.days = days
        self.day = day
        self.target = target
    }
}

/// A change the person made on the timeline, for the caller to write.
public enum TimelineEdit: Sendable, Hashable {
    /// Dragged onto a lane; see `TimelinePlacement`.
    case place(TimelinePlacement)
    /// Dragged onto 无日期: these lose their dates
    /// (`TaskRepo.dropInto(ids, .date(nil), [:])`).
    case unschedule([String])
    /// The left edge dragged: the task starts on `date` and lasts
    /// `duration` (`TaskRepo.setStart`).
    case setStart(taskId: String, date: Day, duration: Int?)
    /// The right edge dragged (`TaskRepo.setDuration`).
    case setDuration(taskId: String, duration: Int?)
}
