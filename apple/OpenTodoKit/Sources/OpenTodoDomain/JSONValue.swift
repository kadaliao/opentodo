// JSON that reads and writes like Dart's `jsonDecode` / `jsonEncode`, for
// data stored or synced as JSON text that must come back byte for byte
// (a filter's rule, with fields from a newer version kept as they were).
//
// Unlike `JSONSerialization`, objects keep their keys in order, numbers keep
// whether they were written as integers, and the output has Dart's form: no
// spaces, keys in order, non-ASCII as is, `/` not escaped, control characters
// as `\n` or `\u001f`, doubles as Dart prints them (`1.0`, `1e+21`).
//
//     let v = JSONValue(parsing: text)      // nil if it isn't JSON
//     v?["field"]?.string
//     v?.encoded()                          // jsonEncode

public indirect enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    /// Keys in the order they came; a key repeated in the text keeps its
    /// first place and its last value, like a Dart map.
    case object(JSONObject)

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var array: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var object: JSONObject? { if case .object(let o) = self { o } else { nil } }

    /// The value for `key`, when this is an object that has it.
    public subscript(key: String) -> JSONValue? { object?[key] }
}

/// A JSON object whose keys keep their order.
public struct JSONObject: Sendable, Hashable, ExpressibleByDictionaryLiteral {
    public private(set) var entries: [(key: String, value: JSONValue)] = []

    public init() {}

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        for (k, v) in elements { self[k] = v }
    }

    public var keys: [String] { entries.map(\.key) }

    public subscript(key: String) -> JSONValue? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let i = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[i].value = newValue } else { entries.remove(at: i) }
            } else if let newValue {
                entries.append((key, newValue))
            }
        }
    }

    public static func == (a: JSONObject, b: JSONObject) -> Bool {
        a.entries.count == b.entries.count
            && zip(a.entries, b.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public func hash(into h: inout Hasher) {
        h.combine(entries.count)
        for e in entries {
            h.combine(e.key)
            h.combine(e.value)
        }
    }
}

// MARK: - Encoding

extension JSONValue {
    /// The text Dart's `jsonEncode` writes for this value.
    public func encoded() -> String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let n): out += String(n)
        case .double(let d): out += dartDoubleString(d)
        case .string(let s): writeString(s, to: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, e) in o.entries.enumerated() {
                if i > 0 { out += "," }
                writeString(e.key, to: &out)
                out += ":"
                e.value.write(to: &out)
            }
            out += "}"
        }
    }
}

private func writeString(_ s: String, to out: inout String) {
    let hex = Array("0123456789abcdef".unicodeScalars)
    var scalars = String.UnicodeScalarView()
    scalars.append("\"")
    for u in s.unicodeScalars {
        switch u {
        case "\"": scalars.append(contentsOf: "\\\"".unicodeScalars)
        case "\\": scalars.append(contentsOf: "\\\\".unicodeScalars)
        case "\u{08}": scalars.append(contentsOf: "\\b".unicodeScalars)
        case "\t": scalars.append(contentsOf: "\\t".unicodeScalars)
        case "\n": scalars.append(contentsOf: "\\n".unicodeScalars)
        case "\u{0C}": scalars.append(contentsOf: "\\f".unicodeScalars)
        case "\r": scalars.append(contentsOf: "\\r".unicodeScalars)
        case _ where u.value < 0x20:
            scalars.append(contentsOf: "\\u00".unicodeScalars)
            scalars.append(hex[Int(u.value >> 4)])
            scalars.append(hex[Int(u.value & 0xF)])
        default: scalars.append(u)
        }
    }
    scalars.append("\"")
    out += String(scalars)
}

/// Dart's `double.toString()` (the JavaScript number format, with `.0` on
/// whole numbers below 1e21).
func dartDoubleString(_ d: Double) -> String {
    if d.isNaN { return "NaN" }
    if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
    if d == 0 { return d.sign == .minus ? "-0.0" : "0.0" }
    // Swift's description is the shortest round-tripping form too; take its
    // digits and exponent and lay them out the Dart way.
    var text = "\(abs(d))"
    var exp = 0
    if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        exp = Int(text[text.index(after: e)...])!
        text = String(text[..<e])
    }
    let point = text.firstIndex(of: ".")
    let intPart = point.map { String(text[..<$0]) } ?? text
    let fracPart = point.map { String(text[text.index(after: $0)...]) } ?? ""
    var digits = intPart + fracPart
    // Position of the decimal point after the first digit of `digits`.
    var n = intPart.count + exp
    while digits.hasPrefix("0") && digits.count > 1 {
        digits.removeFirst()
        n -= 1
    }
    while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }
    let k = digits.count
    let sign = d < 0 ? "-" : ""
    let body: String
    if k <= n && n <= 21 {
        body = digits + String(repeating: "0", count: n - k) + ".0"
    } else if 0 < n && n <= 21 {
        body = String(digits.prefix(n)) + "." + String(digits.dropFirst(n))
    } else if -6 < n && n <= 0 {
        body = "0." + String(repeating: "0", count: -n) + digits
    } else {
        let e = n - 1
        let mantissa = k == 1 ? digits : String(digits.prefix(1)) + "." + String(digits.dropFirst())
        body = mantissa + "e" + (e < 0 ? "-" : "+") + String(abs(e))
    }
    return sign + body
}

// MARK: - Parsing

extension JSONValue {
    /// Parses JSON text as Dart's `jsonDecode` does; nil where that throws a
    /// `FormatException`. Numbers without a fraction or exponent that fit an
    /// `Int` are `.int`, the rest `.double`.
    public init?(parsing text: String) {
        var p = JSONParser(Array(text.utf8))
        p.skipSpace()
        guard let v = p.value() else { return nil }
        p.skipSpace()
        guard p.atEnd else { return nil }
        self = v
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var i = 0
    var depth = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { i >= bytes.count }

    mutating func skipSpace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func literal(_ word: String) -> Bool {
        let w = Array(word.utf8)
        guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { return false }
        i += w.count
        return true
    }

    mutating func value() -> JSONValue? {
        guard i < bytes.count else { return nil }
        switch bytes[i] {
        case UInt8(ascii: "{"): return object()
        case UInt8(ascii: "["): return array()
        case UInt8(ascii: "\""): return string().map(JSONValue.string)
        case UInt8(ascii: "t"): return literal("true") ? .bool(true) : nil
        case UInt8(ascii: "f"): return literal("false") ? .bool(false) : nil
        case UInt8(ascii: "n"): return literal("null") ? .null : nil
        default: return number()
        }
    }

    mutating func object() -> JSONValue? {
        depth += 1
        defer { depth -= 1 }
        guard depth < 10_000 else { return nil }
        i += 1
        var o = JSONObject()
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") {
            i += 1
            return .object(o)
        }
        while true {
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\""), let key = string() else { return nil }
            skipSpace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
            i += 1
            skipSpace()
            guard let v = value() else { return nil }
            o[key] = v
            skipSpace()
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(o) }
            return nil
        }
    }

    mutating func array() -> JSONValue? {
        depth += 1
        defer { depth -= 1 }
        guard depth < 10_000 else { return nil }
        i += 1
        var a: [JSONValue] = []
        skipSpace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") {
            i += 1
            return .array(a)
        }
        while true {
            skipSpace()
            guard let v = value() else { return nil }
            a.append(v)
            skipSpace()
            guard i < bytes.count else { return nil }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
            return nil
        }
    }

    mutating func string() -> String? {
        i += 1 // the opening quote
        var units: [UInt16] = []
        var run = i // start of plain bytes not yet copied
        func flush(_ end: Int) {
            if end > run { units.append(contentsOf: String(decoding: bytes[run..<end], as: UTF8.self).utf16) }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "\"") {
                flush(i)
                i += 1
                return String(decoding: units, as: UTF16.self)
            }
            if b < 0x20 { return nil }
            if b != UInt8(ascii: "\\") {
                i += 1
                continue
            }
            flush(i)
            i += 1
            guard i < bytes.count else { return nil }
            switch bytes[i] {
            case UInt8(ascii: "\""): units.append(0x22)
            case UInt8(ascii: "\\"): units.append(0x5C)
            case UInt8(ascii: "/"): units.append(0x2F)
            case UInt8(ascii: "b"): units.append(0x08)
            case UInt8(ascii: "f"): units.append(0x0C)
            case UInt8(ascii: "n"): units.append(0x0A)
            case UInt8(ascii: "r"): units.append(0x0D)
            case UInt8(ascii: "t"): units.append(0x09)
            case UInt8(ascii: "u"):
                guard i + 4 < bytes.count,
                      let n = UInt16(String(decoding: bytes[i + 1...i + 4], as: UTF8.self), radix: 16)
                else { return nil }
                units.append(n)
                i += 4
            default: return nil
            }
            i += 1
            run = i
        }
        return nil
    }

    mutating func number() -> JSONValue? {
        let start = i
        var isInt = true
        func digits() -> Int {
            let s = i
            while i < bytes.count, (0x30...0x39).contains(bytes[i]) { i += 1 }
            return i - s
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard i < bytes.count, (0x30...0x39).contains(bytes[i]) else { return nil }
        if bytes[i] == UInt8(ascii: "0") { i += 1 } else { _ = digits() }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            isInt = false
            i += 1
            guard digits() > 0 else { return nil }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            isInt = false
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard digits() > 0 else { return nil }
        }
        let text = String(decoding: bytes[start..<i], as: UTF8.self)
        if isInt {
            // Dart reads "-0" as the double -0.0.
            if text == "-0" { return .double(-0.0) }
            if let n = Int(text) { return .int(n) }
        }
        return Double(text).map(JSONValue.double)
    }
}
