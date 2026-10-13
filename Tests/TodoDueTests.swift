import Foundation
import Testing
@testable import PingCore

@MainActor
@Suite struct TodoDueTests {
  private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
  }()
  private func at(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
  }
  private func status(_ due: Date, _ hasTime: Bool, now: Date) -> TodoDue.Status {
    TodoDue.status(due: due, hasTime: hasTime, now: now, calendar: cal)
  }

  @Test func dateOnlyStatus() {
    let now = at(14, 10)
    #expect(status(at(14), false, now: now) == .today)
    #expect(status(at(15), false, now: now) == .tomorrow)
    #expect(status(at(16), false, now: now) == .later)
    #expect(status(at(13), false, now: now) == .overdue(days: 1))
    #expect(status(at(10), false, now: now) == .overdue(days: 4))
  }

  @Test func timedStatus() {
    let now = at(14, 10)
    #expect(status(at(14, 18), true, now: now) == .today)
    #expect(status(at(14, 9, 59), true, now: now) == .overdue(days: 0))
    #expect(status(at(13, 23, 59), true, now: now) == .overdue(days: 1))
    #expect(status(at(15, 8), true, now: now) == .tomorrow)
    #expect(status(at(17, 8), true, now: now) == .later)
  }

  @Test func reminderDate() {
    #expect(TodoDue.reminderDate(due: at(15), hasTime: false, calendar: cal) == at(15, 9))
    #expect(TodoDue.reminderDate(due: at(15, 18, 30), hasTime: true, calendar: cal) == at(15, 18, 30))
  }

  @Test func pendingReminder() {
    func item(due: Date?, hasTime: Bool, done: Bool = false) -> TodoItem {
      TodoItem(id: UUID(), text: "x", createdAt: at(1), doneAt: done ? at(2) : nil,
               due: due, dueHasTime: hasTime)
    }
    let now = at(14, 10)
    #expect(TodoDue.pendingReminder(for: item(due: at(15), hasTime: false), now: now, calendar: cal) == at(15, 9))
    #expect(TodoDue.pendingReminder(for: item(due: at(15), hasTime: false, done: true), now: now, calendar: cal) == nil)
    #expect(TodoDue.pendingReminder(for: item(due: nil, hasTime: false), now: now, calendar: cal) == nil)
    #expect(TodoDue.pendingReminder(for: item(due: at(14), hasTime: false), now: now, calendar: cal) == nil)  // 9:00 passed
    #expect(TodoDue.pendingReminder(for: item(due: at(14, 9), hasTime: true), now: now, calendar: cal) == nil)
    #expect(TodoDue.pendingReminder(for: item(due: at(14, 11), hasTime: true), now: now, calendar: cal) == at(14, 11))
  }
}
