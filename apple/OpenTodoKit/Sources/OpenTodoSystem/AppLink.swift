// Links into the app (`opentodo://…`): what widgets, Spotlight, the share
// extension and App Intents open. The release build answers to `opentodo`,
// the debug build to `opentodo-dev` (its own bundle id, so the two can be
// installed side by side); `AppLink(url)` reads either.
//
//     opentodo://task/<id>        a task's detail
//     opentodo://list/<id>        a list
//     opentodo://today            the 今天 view
//     opentodo://quickadd         the quick-add field / sheet
//     opentodo://habits           the habit check-ins
//     opentodo://countdowns       the countdowns
//     opentodo://focus            the focus timer
//
// Ids are percent-encoded. The scheme a target uses is in its Info.plist
// (`OTURLScheme`, set from the build setting `OT_URL_SCHEME`).

import Foundation

public enum AppLink: Hashable, Sendable {
    case task(String)
    case list(String)
    case today
    case quickAdd
    case habits
    case countdowns
    case focus

    public static let releaseScheme = "opentodo"
    public static let debugScheme = "opentodo-dev"
    public static let schemes: Set<String> = [releaseScheme, debugScheme]

    /// The Info.plist key with the scheme this build answers to.
    public static let schemeInfoKey = "OTURLScheme"

    /// This build's scheme: the bundle's `OTURLScheme`, else `opentodo`.
    public static func scheme(_ bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: schemeInfoKey) as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? releaseScheme
    }

    /// Nil for anything that isn't one of the app's links.
    public init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), Self.schemes.contains(scheme),
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return nil }
        let parts = url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: true)
        let arg = parts.first.flatMap { String($0).removingPercentEncoding }
        switch (host, parts.count) {
        case ("task", 1): guard let arg, !arg.isEmpty else { return nil }; self = .task(arg)
        case ("list", 1): guard let arg, !arg.isEmpty else { return nil }; self = .list(arg)
        case ("today", 0): self = .today
        case ("quickadd", 0): self = .quickAdd
        case ("habits", 0): self = .habits
        case ("countdowns", 0): self = .countdowns
        case ("focus", 0): self = .focus
        default: return nil
        }
    }

    public func url(scheme: String = AppLink.scheme()) -> URL {
        func encoded(_ id: String) -> String {
            id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        }
        let rest = switch self {
        case .task(let id): "task/\(encoded(id))"
        case .list(let id): "list/\(encoded(id))"
        case .today: "today"
        case .quickAdd: "quickadd"
        case .habits: "habits"
        case .countdowns: "countdowns"
        case .focus: "focus"
        }
        return URL(string: "\(scheme)://\(rest)")!
    }
}
