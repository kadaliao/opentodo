// Search (⌘F): whether it's showing — the panel over the window on macOS,
// the 搜索 tab on iOS — and the recent searches. The screens and the
// actions on AppModel are in Search/SearchApp.swift.

import Observation

@Observable
public final class SearchState {
    /// macOS: the search panel is up. iOS: the 搜索 tab is the one showing.
    public var isPresented = false
    /// Newest first; read from `key_values` (`Keys.recentSearches`) when
    /// search first opens, written back by `AppModel.setRecentSearches`.
    public internal(set) var recent: [String] = []
    var recentLoaded = false
    /// Typed in when search next opens (the `search:<query>` debug route).
    public var prefill = ""

    public init() {}

    /// ⌘F.
    public func focus() { isPresented = true }
}
