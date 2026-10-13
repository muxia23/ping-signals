import Foundation
import Testing
@testable import PingCore

@Suite struct TodoQuickParseTests {
  private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
  }()
  /// Wed 2026-10-14 10:00.
  private var now: Date { at(2026, 10, 14, 10, 0) }
  private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
  }
  private func p(_ s: String) -> ParsedTodo { TodoQuickParse.parse(s, now: now, calendar: cal) }

  @Test func spec() {
    #expect(p("交报告 !高 @周五") == ParsedTodo(text: "交报告", priority: .high, due: at(2026, 10, 16), dueHasTime: false))
  }

  @Test func plainTextUntouched() {
    #expect(p("  just   words ") == ParsedTodo(text: "just words", priority: nil, due: nil, dueHasTime: false))
  }

  @Test func priorityWords() {
    for w in ["!高", "!h", "!high", "!1"] { #expect(p("x \(w)").priority == .high) }
    for w in ["!中", "!m", "!med", "!medium", "!2"] { #expect(p("x \(w)").priority == .medium) }
    for w in ["!低", "!l", "!low", "!3"] { #expect(p("x \(w)").priority == .low) }
    #expect(p("x !HIGH").priority == .high)
    #expect(p("x !High").text == "x")
  }

  @Test func duplicatePriorityLastWins() {
    #expect(p("x !h !low").priority == .low)
  }

  @Test func unknownTokensStay() {
    #expect(p("a !foo @bar b").text == "a !foo @bar b")
    #expect(p("a !foo @bar b").due == nil)
  }

  @Test func relativeDays() {
    #expect(p("x @今天").due == at(2026, 10, 14))
    #expect(p("x @today").due == at(2026, 10, 14))
    #expect(p("x @明天").due == at(2026, 10, 15))
    #expect(p("x @Tomorrow").due == at(2026, 10, 15))
    #expect(p("x @tmr").due == at(2026, 10, 15))
    #expect(p("x @后天").due == at(2026, 10, 16))
  }

  @Test func weekdays() {
    #expect(p("x @周三").due == at(2026, 10, 14))      // today counts
    #expect(p("x @周二").due == at(2026, 10, 20))
    #expect(p("x @星期日").due == at(2026, 10, 18))
    #expect(p("x @周天").due == at(2026, 10, 18))
    #expect(p("x @星期天").due == at(2026, 10, 18))
    #expect(p("x @FRI").due == at(2026, 10, 16))
    #expect(p("x @mon").due == at(2026, 10, 19))
    #expect(p("x @sun").due == at(2026, 10, 18))
  }

  @Test func nextWeek() {
    #expect(p("x @下周").due == at(2026, 10, 19))
    #expect(p("x @nextweek").due == at(2026, 10, 19))
    let monday = TodoQuickParse.parse("x @下周", now: at(2026, 10, 19, 8), calendar: cal)
    #expect(monday.due == at(2026, 10, 26))
  }

  @Test func explicitDates() {
    #expect(p("x @10-20").due == at(2026, 10, 20))
    #expect(p("x @10/20").due == at(2026, 10, 20))
    #expect(p("x @10.20").due == at(2026, 10, 20))
    #expect(p("x @10-14").due == at(2026, 10, 14))      // today stays this year
    #expect(p("x @10-13").due == at(2027, 10, 13))      // past rolls over
    #expect(p("x @2027-01-05").due == at(2027, 1, 5))
    #expect(p("x @2020-01-05").due == at(2020, 1, 5))
  }

  @Test func invalidDateStaysInText() {
    let r = p("x @2-30")
    #expect(r.text == "x @2-30" && r.due == nil)
    #expect(p("x @13-01").text == "x @13-01")
    #expect(p("x @2026-02-30").due == nil)
  }

  @Test func times() {
    #expect(p("x @18:00") == ParsedTodo(text: "x", priority: nil, due: at(2026, 10, 14, 18), dueHasTime: true))
    #expect(p("x @9:30").due == at(2026, 10, 14, 9, 30))
    #expect(p("x @24:00").text == "x @24:00")
    #expect(p("x @12:60").text == "x @12:60")
    #expect(p("x 18:00").text == "x 18:00")
  }

  @Test func attachedAndSeparateDateTime() {
    #expect(p("x @明天18:00").due == at(2026, 10, 15, 18))
    #expect(p("x @fri9:30").due == at(2026, 10, 16, 9, 30))
    let r = p("x @10-20 @18:00")
    #expect(r.due == at(2026, 10, 20, 18) && r.dueHasTime && r.text == "x")
    #expect(p("x @18:00 @明天").due == at(2026, 10, 15, 18))
  }
}
