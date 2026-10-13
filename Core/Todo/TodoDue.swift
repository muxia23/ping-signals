import Foundation

/// How a DDL relates to now, and when to remind about it.
public enum TodoDue {
  public enum Status: Equatable, Sendable {
    /// Days late in calendar days, at least 0 (0 = a time that passed earlier today).
    case overdue(days: Int)
    case today, tomorrow, later
  }

  /// Date-only DDLs are overdue from the day after; timed ones from the minute they pass.
  public static func status(due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Status {
    let dueDay = calendar.startOfDay(for: due)
    let today = calendar.startOfDay(for: now)
    let ahead = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
    if hasTime, due < now { return .overdue(days: max(0, -ahead)) }
    if !hasTime, ahead < 0 { return .overdue(days: -ahead) }
    switch ahead {
    case 0: return .today
    case 1: return .tomorrow
    default: return .later
    }
  }

  /// When to notify: the due time, or 9:00 on the due day for a date-only DDL.
  public static func reminderDate(due: Date, hasTime: Bool, calendar: Calendar = .current) -> Date {
    if hasTime { return due }
    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.startOfDay(for: due)) ?? due
  }

  /// The reminder to schedule for an item now, or nil (done, no due, or reminder time already past).
  public static func pendingReminder(for item: TodoItem, now: Date, calendar: Calendar = .current) -> Date? {
    guard !item.isDone, let due = item.due else { return nil }
    let r = reminderDate(due: due, hasTime: item.dueHasTime, calendar: calendar)
    return r > now ? r : nil
  }
}
