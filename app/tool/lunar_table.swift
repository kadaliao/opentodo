import Foundation

// Walks every day from 1900-01-01 to 2101-12-31 through the Chinese calendar
// (ICU, China time) and records each lunar year: where it starts, its months
// in order (with the leap one), and how long each is.
let tz = TimeZone(identifier: "Asia/Shanghai")!
var greg = Calendar(identifier: .gregorian); greg.timeZone = tz
var chinese = Calendar(identifier: .chinese); chinese.timeZone = tz

struct Month { var month: Int; var leap: Bool; var length: Int }
struct Year { var start: DateComponents; var months: [Month] }

var years: [Int: Year] = [:]
var currentYear: Int? = nil
var date = greg.date(from: DateComponents(year: 1900, month: 1, day: 1, hour: 12))!
let end = greg.date(from: DateComponents(year: 2101, month: 12, day: 31, hour: 12))!
while date <= end {
  let c = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
  let g = greg.dateComponents([.year, .month, .day], from: date)
  let leap = c.isLeapMonth ?? false
  if c.month == 1 && c.day == 1 && !leap {
    currentYear = g.year!
    years[g.year!] = Year(start: g, months: [])
  }
  if let y = currentYear {
    if c.day == 1 { years[y]!.months.append(Month(month: c.month!, leap: leap, length: 0)) }
    if !years[y]!.months.isEmpty { years[y]!.months[years[y]!.months.count - 1].length += 1 }
  }
  date = greg.date(byAdding: .day, value: 1, to: date)!
}

var out: [String] = []
for y in 1900...2100 {
  let yr = years[y]!
  let jan1 = greg.date(from: DateComponents(year: y, month: 1, day: 1, hour: 12))!
  let start = greg.date(from: DateComponents(year: y, month: yr.start.month, day: yr.start.day, hour: 12))!
  let offset = greg.dateComponents([.day], from: jan1, to: start).day!
  let leapMonth = yr.months.first(where: { $0.leap })?.month ?? 0
  precondition(yr.months.count == (leapMonth == 0 ? 12 : 13), "\(y) months \(yr.months.count)")
  var bits = 0
  for (i, m) in yr.months.enumerated() {
    precondition(m.length == 29 || m.length == 30, "\(y) month \(m.month) len \(m.length)")
    if m.length == 30 { bits |= 1 << i }
  }
  out.append(String(format: "0x%06x", (offset << 17) | (leapMonth << 13) | bits))
  if [2025, 2026, 2027, 2028, 2033].contains(y) {
    FileHandle.standardError.write("\(y): starts \(yr.start.month!)/\(yr.start.day!), leap \(leapMonth), lengths \(yr.months.map { "\($0.leap ? "闰" : "")\($0.month):\($0.length)" }.joined(separator: " "))\n".data(using: .utf8)!)
  }
}
var lines: [String] = []
for i in stride(from: 0, to: out.count, by: 8) {
  lines.append("  " + out[i..<min(i + 8, out.count)].joined(separator: ", ") + ",")
}
print(lines.joined(separator: "\n"))
