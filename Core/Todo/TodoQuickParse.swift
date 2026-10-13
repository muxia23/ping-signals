import Foundation

public struct ParsedTodo: Equatable, Sendable {
  public var text: String
  public var priority: TodoPriority?
  public var due: Date?
  public var dueHasTime: Bool
}

/// Pulls `!priority` and `@date`/`@time` words out of a quick-add line.
public enum TodoQuickParse {
  private static let priorities: [String: TodoPriority] = [
    "高": .high, "h": .high, "high": .high, "1": .high,
    "中": .medium, "m": .medium, "med": .medium, "medium": .medium, "2": .medium,
    "低": .low, "l": .low, "low": .low, "3": .low,
  ]
  private static let offsets: [String: Int] = [
    "今天": 0, "today": 0, "明天": 1, "tomorrow": 1, "tmr": 1, "后天": 2,
  ]
  /// Calendar weekday numbers (1 = Sunday).
  private static let weekdays: [String: Int] = {
    var m: [String: Int] = [:]
    for (i, c) in ["一", "二", "三", "四", "五", "六"].enumerated() { m["周" + c] = i + 2; m["星期" + c] = i + 2 }
    for k in ["周日", "周天", "星期日", "星期天", "sun"] { m[k] = 1 }
    for (i, k) in ["mon", "tue", "wed", "thu", "fri", "sat"].enumerated() { m[k] = i + 2 }
    return m
  }()

  public static func parse(_ input: String, now: Date, calendar: Calendar = .current) -> ParsedTodo {
    let today = calendar.startOfDay(for: now)
    var kept: [Substring] = []
    var priority: TodoPriority?
    var day: Date?
    var time: (h: Int, m: Int)?

    for word in input.split(whereSeparator: \.isWhitespace) {
      let w = word.lowercased()
      if w.hasPrefix("!"), let p = priorities[String(w.dropFirst())] {
        priority = p
      } else if w.hasPrefix("@"), let r = dateTime(String(w.dropFirst()), today: today, calendar: calendar) {
        if let d = r.day { day = d }
        if let t = r.time { time = t }
      } else {
        kept.append(word)
      }
    }

    let text = kept.joined(separator: " ")
    guard day != nil || time != nil else { return ParsedTodo(text: text, priority: priority, due: nil, dueHasTime: false) }
    let base = day ?? today
    guard let t = time else { return ParsedTodo(text: text, priority: priority, due: base, dueHasTime: false) }
    let due = calendar.date(bySettingHour: t.h, minute: t.m, second: 0, of: base)
    return ParsedTodo(text: text, priority: priority, due: due, dueHasTime: true)
  }

  /// `body` is the word after `@`: a date, a time, or a date with a time attached.
  private static func dateTime(_ body: String, today: Date, calendar: Calendar) -> (day: Date?, time: (h: Int, m: Int)?)? {
    if let t = clock(body) { return (nil, t) }
    if let r = body.range(of: #"\d{1,2}:\d{2}$"#, options: .regularExpression),
       let t = clock(String(body[r])), let d = date(String(body[..<r.lowerBound]), today: today, calendar: calendar) {
      return (d, t)
    }
    if let d = date(body, today: today, calendar: calendar) { return (d, nil) }
    return nil
  }

  private static func clock(_ s: String) -> (h: Int, m: Int)? {
    let parts = s.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
          let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
    return (h, m)
  }

  private static func date(_ s: String, today: Date, calendar: Calendar) -> Date? {
    if let n = offsets[s] { return calendar.date(byAdding: .day, value: n, to: today) }
    if let wd = weekdays[s] {
      let cur = calendar.component(.weekday, from: today)
      return calendar.date(byAdding: .day, value: (wd - cur + 7) % 7, to: today)
    }
    if s == "下周" || s == "nextweek" {
      let cur = calendar.component(.weekday, from: today)
      let delta = (2 - cur + 7) % 7
      return calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: today)
    }
    let nums = s.split(omittingEmptySubsequences: false, whereSeparator: { "-/.".contains($0) }).map { Int($0) }
    if s.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil,
       nums.count == 3, let y = nums[0], let m = nums[1], let d = nums[2] {
      return valid(y, m, d, calendar)
    }
    if s.range(of: #"^\d{1,2}[-/.]\d{1,2}$"#, options: .regularExpression) != nil,
       nums.count == 2, let m = nums[0], let d = nums[1] {
      let y = calendar.component(.year, from: today)
      guard let this = valid(y, m, d, calendar) else { return nil }
      return this >= today ? this : valid(y + 1, m, d, calendar)
    }
    return nil
  }

  /// Rejects overflowing dates like 2-30 that Calendar would silently roll over.
  private static func valid(_ y: Int, _ m: Int, _ d: Int, _ calendar: Calendar) -> Date? {
    guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return c.year == y && c.month == m && c.day == d ? date : nil
  }
}
