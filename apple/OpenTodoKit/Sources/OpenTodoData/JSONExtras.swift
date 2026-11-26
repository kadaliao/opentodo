// What the data layer reads and builds JSON with, on top of the domain's
// `JSONValue` (Dart's `jsonDecode` / `jsonEncode`, keys kept in order):
// lenient typed reads that give nil for a missing or mistyped value, and
// objects built from ordered pairs.

import Foundation

public struct JSONParseError: Error, CustomStringConvertible {
    public init() {}
    public var description: String { "not JSON" }
}

extension JSONValue {
    /// An object with these fields, in this order.
    public static func fields(_ pairs: [(String, JSONValue)]) -> JSONValue {
        var o = JSONObject()
        for (k, v) in pairs { o[k] = v }
        return .object(o)
    }

    /// An object's fields in order; nil for anything else.
    public var pairs: [(String, JSONValue)]? { object?.entries.map { ($0.key, $0.value) } }

    public init(_ value: String?) { self = value.map(JSONValue.string) ?? .null }
    public init(_ value: Int?) { self = value.map(JSONValue.int) ?? .null }

    /// Parses UTF-8 JSON; nil if it isn't JSON.
    public init?(parsing data: Data) {
        self.init(parsing: String(decoding: data, as: UTF8.self))
    }

    /// Nil instead of an error for text that isn't JSON.
    public static func parse(_ text: String) -> JSONValue? { JSONValue(parsing: text) }

    /// Parses, throwing for text that isn't JSON.
    public static func decode(_ text: String) throws -> JSONValue {
        guard let v = JSONValue(parsing: text) else { throw JSONParseError() }
        return v
    }

    public var encodedData: Data { Data(encoded().utf8) }

    public var stringValue: String? { string }

    public var boolValue: Bool? {
        if case let .bool(b) = self { b } else { nil }
    }

    /// A number as an integer, truncating a fraction like Dart's
    /// `(v as num).toInt()`.
    public var intValue: Int? {
        switch self {
        case let .int(i): i
        case let .double(d) where d.isFinite && abs(d) < 9.2e18: Int(d)
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case let .int(i): Double(i)
        case let .double(d): d
        default: nil
        }
    }

    public var arrayValue: [JSONValue]? { array }

    public var isObject: Bool { object != nil }
}
