//
//  CronParser.swift
//  SwiftCronParser
//
//  Parses a 5-field cron expression into its fields, a human description, and the
//  next run times. Dependency-free and deterministic (time is injected).
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Parses a standard 5-field cron expression (`minute hour day month weekday`).
///
/// Deterministic: the current time and calendar are passed in, so results are
/// fully testable and time-zone explicit.
///
/// ```swift
/// import CronParser
///
/// let r = CronParser.parse("*/15 * * * *", now: Date(), calendar: .current)
/// print(r.description)   // "Every 15 minutes."
/// print(r.nextRuns)      // next 5 fire times
/// ```
public enum CronParser {

    /// Parses `expr` relative to `now`, using `calendar` for all date math.
    ///
    /// - Returns: a ``Result`` with the parsed fields, a human description, and the
    ///   next 5 run times — or a populated `error` when the expression is invalid.
    public static func parse(_ expr: String, now: Date, calendar: Calendar) -> Result {
        let parts = expr.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let names = ["Minute", "Hour", "Day", "Month", "Week"]
        guard parts.count == 5 else {
            return Result(fields: [], description: "", nextRuns: [],
                          error: "A cron expression needs 5 fields:  minute  hour  day  month  weekday")
        }
        let fields = Array(zip(names, parts)).map { (name: $0.0, value: $0.1) }
        guard let minutes = set(parts[0], 0, 59), let hours = set(parts[1], 0, 23),
              let days = set(parts[2], 1, 31), let months = set(parts[3], 1, 12),
              let weekdaysRaw = set(parts[4], 0, 7) else {
            return Result(fields: fields, description: "", nextRuns: [], error: "Couldn't parse one of the fields.")
        }
        let weekdays = Set(weekdaysRaw.map { $0 == 7 ? 0 : $0 })   // both 0 and 7 mean Sunday
        // Vixie/cronie treat a day field as "unrestricted" whenever its text STARTS
        // with '*' (so "*/2" keeps AND combination, like the real daemon).
        let runs = nextRuns(minutes, hours, days, months, weekdays,
                            domRestricted: !parts[2].hasPrefix("*"), dowRestricted: !parts[4].hasPrefix("*"),
                            now: now, cal: calendar, count: 5)
        return Result(fields: fields, description: describe(parts), nextRuns: runs, error: nil)
    }

    /// A single field → the set of matching values. Handles `*`, `*/n`, `a-b`, `a-b/n`, `a,b`, `n`.
    private static func set(_ field: String, _ lo: Int, _ hi: Int) -> Set<Int>? {
        var result = Set<Int>()
        for part in field.split(separator: ",") {
            let p = String(part)
            var step = 1, range = p
            if let slash = p.firstIndex(of: "/") {
                step = Int(p[p.index(after: slash)...]) ?? 0
                range = String(p[..<slash])
            }
            var start = lo, end = hi
            if range == "*" {
            } else if let dash = range.firstIndex(of: "-") {
                start = Int(range[..<dash]) ?? -1
                end = Int(range[range.index(after: dash)...]) ?? -1
            } else if let single = Int(range) {
                start = single; end = single
            } else { return nil }
            guard start >= lo, end <= hi, start <= end, step > 0 else { return nil }
            var v = start
            while v <= end { result.insert(v); v += step }
        }
        return result.isEmpty ? nil : result
    }

    private static func nextRuns(_ minutes: Set<Int>, _ hours: Set<Int>, _ days: Set<Int>,
                                 _ months: Set<Int>, _ weekdays: Set<Int>,
                                 domRestricted: Bool, dowRestricted: Bool,
                                 now: Date, cal: Calendar, count: Int) -> [Date] {
        var runs: [Date] = []
        // Floor `now` to its minute (date(bySetting:.second) would jump to the NEXT
        // minute boundary), then step forward one minute at a time.
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        comps.second = 0
        var t = (cal.date(from: comps) ?? now).addingTimeInterval(60)
        // Scan up to 8 years out: the worst gap to the next matching date for any
        // satisfiable expression is a Feb-29 schedule across a non-leap century year
        // (e.g. 2096-03-01 → 2104-02-29, just under 8 years). An empty result within
        // this horizon therefore means the expression never fires.
        let horizon = cal.date(byAdding: .year, value: 8, to: now) ?? now.addingTimeInterval(8 * 366 * 86_400)
        while runs.count < count, t < horizon {
            let c = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: t)
            let wd = ((c.weekday ?? 1) - 1)   // Calendar 1=Sun → cron 0=Sun
            // Vixie cron: day-of-month and day-of-week are ORed when BOTH are restricted.
            let dayOK = (domRestricted && dowRestricted)
                ? (days.contains(c.day ?? -1) || weekdays.contains(wd))
                : (days.contains(c.day ?? -1) && weekdays.contains(wd))
            guard months.contains(c.month ?? -1), dayOK else {
                // Nothing on this day can match — jump to the start of the next day.
                t = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t)) ?? t.addingTimeInterval(86_400)
                continue
            }
            if minutes.contains(c.minute ?? -1), hours.contains(c.hour ?? -1) {
                runs.append(t)
            }
            t = t.addingTimeInterval(60)
        }
        return runs
    }

    private static func describe(_ p: [String]) -> String {
        var bits: [String] = []
        if p[0] == "*" { bits.append("every minute") }
        else if p[0].hasPrefix("*/"), let n = Int(p[0].dropFirst(2)) { bits.append("every \(n) minutes") }
        else if let dash = p[0].firstIndex(of: "-") { bits.append("minutes \(p[0][..<dash])–\(p[0][p[0].index(after: dash)...])") }
        else { bits.append("at minute \(p[0])") }

        if p[1] != "*" {
            if p[1].hasPrefix("*/"), let n = Int(p[1].dropFirst(2)) { bits.append("every \(n) hours") }
            else if let dash = p[1].firstIndex(of: "-") { bits.append("hours \(p[1][..<dash]) through \(p[1][p[1].index(after: dash)...])") }
            else { bits.append("hour \(p[1])") }
        }
        let dows = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        func day(_ n: Int) -> String { (0...7).contains(n) ? dows[n % 7] : "\(n)" }   // 7 = Sunday too
        if p[4] != "*" {
            if let dash = p[4].firstIndex(of: "-"), let a = Int(p[4][..<dash]), let b = Int(p[4][p[4].index(after: dash)...]) {
                bits.append("\(day(a)) through \(day(b))")
            } else if let n = Int(p[4]) { bits.append("on \(day(n))") }
            else { bits.append("weekday \(p[4])") }
        }
        if p[3] != "*" { bits.append("in month \(p[3])") }
        if p[2] != "*" { bits.append("on day \(p[2])") }
        let s = bits.joined(separator: ", ")
        return s.isEmpty ? "Every minute." : s.prefix(1).uppercased() + s.dropFirst() + "."
    }
}
