// The last search worked out, kept while nothing it depends on changes: the
// panel's and the page's bodies run again for every cursor move and every
// redraw, and searching 5000 tasks (pinyin too) takes a frame or more
// (PerformanceTests: zhoubao 21 ms in a release build).

import OpenTodoDomain

final class SearchMemo {
    private var query = ""
    private var data: SearchData?
    private var recent: RecentSearches?
    private var last: SearchModel?

    /// `SearchModel(query:data:recent:)`, from the last time if all three
    /// are the same. (The window's `searchData` is the same value for the
    /// same snapshot, so comparing it is quick.)
    func model(query: String, data: SearchData, recent: RecentSearches) -> SearchModel {
        if let last, query == self.query, recent == self.recent, data == self.data { return last }
        let model = SearchModel(query: query, data: data, recent: recent)
        self.query = query
        self.data = data
        self.recent = recent
        last = model
        return model
    }
}
