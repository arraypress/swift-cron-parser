//
//  CronParserTests.swift
//  Tests for SwiftCronParser
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import CronParser

final class CronParserTests: XCTestCase {

    // Fixed reference point: Thursday 2026-07-09 10:07 UTC.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private lazy var now: Date = cal.date(from: DateComponents(
        year: 2026, month: 7, day: 9, hour: 10, minute: 7))!

    func testEvery15Minutes() {
        let r = CronParser.parse("*/15 * * * *", now: now, calendar: cal)
        XCTAssertNil(r.error)
        XCTAssertEqual(r.description, "Every 15 minutes.")
        XCTAssertEqual(r.nextRuns.count, 5)
        let first = cal.dateComponents([.hour, .minute], from: r.nextRuns[0])
        XCTAssertEqual(first.hour, 10)
        XCTAssertEqual(first.minute, 15)   // 10:07 → next quarter is 10:15
        for run in r.nextRuns {
            XCTAssertTrue([0, 15, 30, 45].contains(cal.component(.minute, from: run)))
        }
    }

    func testDailyAtNineRollsToNextDay() {
        let r = CronParser.parse("0 9 * * *", now: now, calendar: cal)
        XCTAssertNil(r.error)
        let c = cal.dateComponents([.day, .hour, .minute], from: r.nextRuns[0])
        XCTAssertEqual(c.hour, 9)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(c.day, 10)   // 09:00 already passed today → tomorrow
    }

    func testMinuteList() {
        let r = CronParser.parse("0,30 * * * *", now: now, calendar: cal)
        XCTAssertNil(r.error)
        for run in r.nextRuns {
            XCTAssertTrue([0, 30].contains(cal.component(.minute, from: run)))
        }
    }

    func testWeekdayMondayOnly() {
        let r = CronParser.parse("0 0 * * 1", now: now, calendar: cal)
        XCTAssertNil(r.error)
        XCTAssertFalse(r.nextRuns.isEmpty)
        for run in r.nextRuns {
            XCTAssertEqual(cal.component(.weekday, from: run), 2)   // Calendar: 1=Sun, 2=Mon
            XCTAssertEqual(cal.component(.hour, from: run), 0)
            XCTAssertEqual(cal.component(.minute, from: run), 0)
        }
    }

    func testFieldsAreLabeled() {
        let r = CronParser.parse("0 9 * * 1", now: now, calendar: cal)
        XCTAssertEqual(r.fields.map(\.name), ["Minute", "Hour", "Day", "Month", "Week"])
        XCTAssertEqual(r.fields.map(\.value), ["0", "9", "*", "*", "1"])
    }

    func testWrongFieldCountIsAnError() {
        let r = CronParser.parse("* * * *", now: now, calendar: cal)
        XCTAssertNotNil(r.error)
        XCTAssertTrue(r.nextRuns.isEmpty)
    }

    func testOutOfRangeFieldIsAnError() {
        let r = CronParser.parse("99 * * * *", now: now, calendar: cal)   // minute 99 > 59
        XCTAssertNotNil(r.error)
    }

    func testEveryMinuteDescription() {
        XCTAssertEqual(CronParser.parse("* * * * *", now: now, calendar: cal).description, "Every minute.")
    }

    // MARK: - Regressions

    // Regression: the old 366-day scan cap returned [] for schedules whose next
    // fire is further out (e.g. Feb 29 from mid-2026 → 2028-02-29).
    func testLeapDayScheduleFindsRunsBeyondOneYear() {
        let r = CronParser.parse("0 0 29 2 *", now: now, calendar: cal)
        XCTAssertNil(r.error)
        XCTAssertFalse(r.nextRuns.isEmpty)
        let first = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.nextRuns[0])
        XCTAssertEqual(first.year, 2028)   // next leap day after 2026-07-09
        XCTAssertEqual(first.month, 2)
        XCTAssertEqual(first.day, 29)
        XCTAssertEqual(first.hour, 0)
        XCTAssertEqual(first.minute, 0)
        for run in r.nextRuns {
            XCTAssertEqual(cal.component(.month, from: run), 2)
            XCTAssertEqual(cal.component(.day, from: run), 29)
        }
    }

    // A syntactically valid but never-satisfiable date (Feb 31) yields no runs and
    // no error — and returns quickly thanks to whole-day skipping.
    func testImpossibleDateNeverFires() {
        let r = CronParser.parse("0 0 31 2 *", now: now, calendar: cal)
        XCTAssertNil(r.error)
        XCTAssertTrue(r.nextRuns.isEmpty)
    }

    // Regression: "*/n" in a day field must count as UNRESTRICTED (Vixie DOM_STAR),
    // so DOM and DOW are ANDed — this line fires only on odd-numbered Mondays.
    func testStepDayOfMonthWithWeekdayIsANDed() {
        let r = CronParser.parse("0 0 */2 * 1", now: now, calendar: cal)
        XCTAssertNil(r.error)
        XCTAssertEqual(r.nextRuns.count, 5)
        let first = cal.dateComponents([.month, .day], from: r.nextRuns[0])
        XCTAssertEqual(first.month, 7)
        XCTAssertEqual(first.day, 13)   // Mon Jul 13, not Fri Jul 17 / Sun Jul 19
        for run in r.nextRuns {
            XCTAssertEqual(cal.component(.weekday, from: run), 2)             // Monday
            XCTAssertEqual(cal.component(.day, from: run) % 2, 1)             // odd day
        }
    }

    // Symmetric case: "*/2" in the weekday field is unrestricted too, so this fires
    // only on the 15th when the 15th is an even cron weekday (Sun/Tue/Thu/Sat).
    func testStepWeekdayWithDayOfMonthIsANDed() {
        let r = CronParser.parse("0 0 15 * */2", now: now, calendar: cal)
        XCTAssertNil(r.error)
        XCTAssertFalse(r.nextRuns.isEmpty)
        for run in r.nextRuns {
            XCTAssertEqual(cal.component(.day, from: run), 15)
            XCTAssertTrue([1, 3, 5, 7].contains(cal.component(.weekday, from: run)))   // cron 0/2/4/6
        }
    }

    // Both day fields genuinely restricted → Vixie ORs them (unchanged behavior).
    func testRestrictedDomAndDowAreORed() {
        let r = CronParser.parse("0 0 15 * 1", now: now, calendar: cal)
        XCTAssertNil(r.error)
        for run in r.nextRuns {
            let isMon = cal.component(.weekday, from: run) == 2
            let is15th = cal.component(.day, from: run) == 15
            XCTAssertTrue(isMon || is15th)
        }
        // Mon Jul 13 comes before Wed Jul 15, so the OR must surface it first.
        XCTAssertEqual(cal.component(.day, from: r.nextRuns[0]), 13)
    }

    // Regression: weekday 7 parsed as Sunday but described as the literal "7".
    func testWeekdaySevenIsDescribedAsSunday() {
        let r = CronParser.parse("0 0 * * 7", now: now, calendar: cal)
        XCTAssertEqual(r.description, "At minute 0, hour 0, on Sunday.")
        for run in r.nextRuns {
            XCTAssertEqual(cal.component(.weekday, from: run), 1)   // Calendar: 1=Sun
        }
        let range = CronParser.parse("0 0 * * 5-7", now: now, calendar: cal)
        XCTAssertEqual(range.description, "At minute 0, hour 0, Friday through Sunday.")
    }
}
