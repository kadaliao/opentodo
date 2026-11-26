// Name-based UUIDs (RFC 9562 version 5: SHA-1 of a namespace and a name),
// for records whose id is worked out from what they are, so two devices
// that make "the same thing" offline make the same id and sync merges them
// into one row. The Dart version uses `Uuid().v5(namespace, name)` from the
// `uuid` package for repeating-task copies; this gives the same ids.
//
//     uuidV5(namespace: habitCheckinNamespace, name: "\(habitId)/2026-11-15")
//
// SHA-1 is written out here so the domain keeps depending on Foundation
// only; it is used for ids, not for anything secret.

import Foundation

/// The version 5 UUID of `name` (its UTF-8 bytes) in `namespace` (a UUID
/// string), lowercase with dashes, like Dart's `Uuid().v5`.
public func uuidV5(namespace: String, name: String) -> String {
    guard let ns = UUID(uuidString: namespace) else {
        preconditionFailure("not a UUID: \(namespace)")
    }
    let u = ns.uuid
    var bytes: [UInt8] = [
        u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
        u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15,
    ]
    bytes.append(contentsOf: Array(name.utf8))
    var hash = Array(sha1(bytes).prefix(16))
    hash[6] = (hash[6] & 0x0F) | 0x50
    hash[8] = (hash[8] & 0x3F) | 0x80
    let hex = hash.map { b in
        let s = String(b, radix: 16)
        return b < 16 ? "0" + s : s
    }.joined()
    let i = hex.startIndex
    func part(_ from: Int, _ to: Int) -> Substring {
        hex[hex.index(i, offsetBy: from)..<hex.index(i, offsetBy: to)]
    }
    return "\(part(0, 8))-\(part(8, 12))-\(part(12, 16))-\(part(16, 20))-\(part(20, 32))"
}

/// SHA-1 (FIPS 180-4) of `message`: 20 bytes.
func sha1(_ message: [UInt8]) -> [UInt8] {
    var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
    var data = message
    let bitLength = UInt64(message.count) * 8
    data.append(0x80)
    while data.count % 64 != 56 { data.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) {
        data.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
    }

    var w = [UInt32](repeating: 0, count: 80)
    for chunk in stride(from: 0, to: data.count, by: 64) {
        for t in 0..<16 {
            let j = chunk + t * 4
            w[t] = UInt32(data[j]) << 24 | UInt32(data[j + 1]) << 16 | UInt32(data[j + 2]) << 8 | UInt32(data[j + 3])
        }
        for t in 16..<80 {
            w[t] = rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
        for t in 0..<80 {
            let f: UInt32
            let k: UInt32
            switch t {
            case 0..<20: f = (b & c) | (~b & d); k = 0x5A82_7999
            case 20..<40: f = b ^ c ^ d; k = 0x6ED9_EBA1
            case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1B_BCDC
            default: f = b ^ c ^ d; k = 0xCA62_C1D6
            }
            let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[t]
            e = d
            d = c
            c = rotl(b, 30)
            b = a
            a = temp
        }
        h[0] = h[0] &+ a
        h[1] = h[1] &+ b
        h[2] = h[2] &+ c
        h[3] = h[3] &+ d
        h[4] = h[4] &+ e
    }
    return h.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> UInt32(24 - 8 * $0)) } }
}

private func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
