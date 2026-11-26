// What another app shares (text, a link, a web page's title) as a task for
// the inbox: the share extension shows the draft, the person may change the
// title and the list, then `SharedWriter.add` saves it.

import Foundation

/// What came in through the share sheet.
public struct SharedItem: Hashable, Sendable {
    public var text: String?
    public var url: URL?
    /// The page title the sharing app gave (Safari does), if any.
    public var pageTitle: String?

    public init(text: String? = nil, url: URL? = nil, pageTitle: String? = nil) {
        self.text = text
        self.url = url
        self.pageTitle = pageTitle
    }
}

/// The task to make from it.
public struct ShareDraft: Hashable, Sendable {
    public var title: String
    /// The description: the link, and any text beyond the title.
    public var content: String

    public init(title: String, content: String = "") {
        self.title = title
        self.content = content
    }
}

/// Longest title taken from shared text; the rest goes to the description.
public let shareTitleLimit = 200

/// The title is the page's title, else the text's first line (a link inside
/// the text taken out of it), else the link's address; the link and the
/// rest of the text go in the description. A link found in the text counts
/// as the shared link when none was given.
public func shareDraft(_ item: SharedItem) -> ShareDraft {
    func clean(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
    var url = item.url
    var text = clean(item.text)
    if let t = text {
        let links = links(in: t)
        if url == nil { url = links.first?.url }
        // The text is only the link (or the given link is in it): leave it out.
        if let u = url, let found = links.first(where: { $0.url.absoluteString == u.absoluteString || $0.text == u.absoluteString }) {
            text = clean(t.replacingOccurrences(of: found.text, with: " ")
                .replacingOccurrences(of: "  ", with: " "))
        }
    }

    var lines = text.map { $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
    lines.removeAll(where: \.isEmpty)
    var title = clean(item.pageTitle)
    var rest: [String] = lines
    if title == nil, let first = lines.first {
        if first.count > shareTitleLimit {
            title = String(first.prefix(shareTitleLimit))
            rest = [String(first.dropFirst(shareTitleLimit))] + lines.dropFirst()
        } else {
            title = first
            rest = Array(lines.dropFirst())
        }
    }
    if title == nil, let u = url { title = displayAddress(u) }
    var content = [String]()
    if let u = url { content.append(u.absoluteString) }
    if !rest.isEmpty { content.append(rest.joined(separator: "\n")) }
    return ShareDraft(title: title ?? "", content: content.joined(separator: "\n\n"))
}

/// example.com/path, for a link without a title.
public func displayAddress(_ url: URL) -> String {
    guard let host = url.host(percentEncoded: false) else { return url.absoluteString }
    let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let path = url.path(percentEncoded: false)
    return path.isEmpty || path == "/" ? h : h + path
}

private func links(in text: String) -> [(url: URL, text: String)] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
    let ns = text as NSString
    return detector.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
        guard let u = m.url, u.scheme == "http" || u.scheme == "https" else { return nil }
        return (u, ns.substring(with: m.range))
    }
}
