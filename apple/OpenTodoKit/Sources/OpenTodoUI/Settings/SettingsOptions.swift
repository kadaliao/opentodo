// What the settings offer and how it reads, as plain values: the choices of
// each picker (照 app/lib/ui/settings_page.dart, plus 专注 and 日历), their
// labels, and the notification status line. The views only lay these out.

import OpenTodoData
import OpenTodoDomain

enum SettingsOptions {
    /// 时间段默认时长.
    static let spans = [15, 30, 45, 60, 90, 120, 180]
    /// 稍后提醒.
    static let snoozes = [5, 10, 15, 30, 60]
    static let pomodoros = [15, 20, 25, 30, 35, 40, 45, 50, 60, 90]
    static let shortBreaks = [3, 5, 10, 15]
    static let longBreaks = [10, 15, 20, 25, 30]
    static let longBreakEvery = [2, 3, 4, 5, 6]

    /// 15分钟, 1小时, 1小时30分钟.
    static func minutes(_ m: Int) -> String {
        if m < 60 { return "\(m)分钟" }
        return m % 60 == 0 ? "\(m / 60)小时" : "\(m / 60)小时\(m % 60)分钟"
    }

    /// The default reminders a task can get: none, or one preset.
    static func reminderChoices(allDay: Bool) -> [[Int]] {
        [[]] + (allDay ? allDayReminderPresets : timedReminderPresets).map { [$0] }
    }

    static func reminderLabel(_ r: [Int], allDay: Bool) -> String {
        r.isEmpty ? "无" : remindersSummary(r, allDay: allDay)
    }

    /// `options`, with `value` added at the end when it isn't one of them
    /// (set by a newer version, or elsewhere): shown and kept as it is.
    static func including<T: Equatable>(_ options: [T], _ value: T) -> [T] {
        options.contains(value) ? options : options + [value]
    }
}

/// The 系统通知 row: what it says and what its button does.
struct NotificationStatus: Equatable {
    var text: String
    var warning: Bool
    var button: String

    /// `allowed`: nil while never asked, then the system's answer.
    init(allowed: Bool?) {
        if allowed == false {
            self.init(text: "已关闭，提醒不会弹出", warning: true, button: "去开启")
        } else if allowed == nil {
            self.init(text: "第一次有提醒要排时会请你允许通知", warning: false, button: "系统设置")
        } else {
            self.init(text: "提醒到点时由系统弹出通知", warning: false, button: "系统设置")
        }
    }

    init(text: String, warning: Bool, button: String) {
        self.text = text
        self.warning = warning
        self.button = button
    }
}

/// 关于.
enum AboutInfo {
    static let license = "AGPL-3.0"
    static let licenseURL = "https://www.gnu.org/licenses/agpl-3.0.html"
    static let repository = "https://github.com/kadaliao/opentodo"

    /// 0.1.0 (1), from the bundle.
    static func version(_ info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?) where s != b: return "\(s) (\(b))"
        case let (s?, _): return s
        default: return "—"
        }
    }
}
