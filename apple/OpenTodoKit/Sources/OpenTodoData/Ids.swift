// Record ids, as the Flutter version makes them (package:uuid): new rows
// get a time-ordered UUID v7; a finished occurrence of a repeating task
// gets a UUID v5 derived from the task and its date, so two devices
// finishing the same occurrence offline end up with one copy. Lowercase
// text, like Dart's. UUID v5 is the domain's `uuidV5`.

import Foundation

public enum Ids {
    /// Namespace of the occurrence ids (`_occurrenceNamespace` in repo.dart).
    public static let occurrenceNamespace = "b3e0b216-dc4f-4498-98bb-c1e895f8613a"

    /// A new id: UUID v7 (48-bit Unix milliseconds, then random bits).
    public static func newId(now: Date = .now) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(max(0, nowMilliseconds(now)))
        for i in 0 ..< 6 { bytes[i] = UInt8((ms >> (8 * (5 - UInt64(i)))) & 0xFF) }
        var rng = SystemRandomNumberGenerator()
        for i in 6 ..< 16 { bytes[i] = rng.next() }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return format(bytes)
    }

    /// The id of the finished copy of `id`'s occurrence on `dueDate`.
    public static func occurrenceId(of id: String, dueDate: Day?) -> String {
        uuidV5(namespace: occurrenceNamespace, name: "\(id)/\(dueDate?.key ?? "null")")
    }

    private static func format(_ b: [UInt8]) -> String {
        let hex = b.map { String(format: "%02x", $0) }
        return [hex[0 ..< 4], hex[4 ..< 6], hex[6 ..< 8], hex[8 ..< 10], hex[10 ..< 16]]
            .map { $0.joined() }.joined(separator: "-")
    }
}
