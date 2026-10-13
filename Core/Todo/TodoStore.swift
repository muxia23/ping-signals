import Foundation
import Observation

/// Where the user was when the On My Way ping fired.
public struct TodoContext: Equatable, Sendable {
  public var appName: String?
  public var bundleID: String?
  public var windowTitle: String?
  public var url: String?
  public init(appName: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, url: String? = nil) {
    self.appName = appName; self.bundleID = bundleID; self.windowTitle = windowTitle; self.url = url
  }
}

public enum TodoPriority: Int, Codable, CaseIterable, Comparable, Sendable {
  case low = 1, medium = 2, high = 3
  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var text: String
  public let createdAt: Date
  public var doneAt: Date?
  public var appName: String?
  public var bundleID: String?
  public var windowTitle: String?
  public var url: String?
  public var priority: TodoPriority?
  /// Date-only DDL: start of that day in the local calendar.
  public var due: Date?
  public var dueHasTime: Bool

  public var isDone: Bool { doneAt != nil }

  public init(id: UUID, text: String, createdAt: Date, doneAt: Date? = nil, appName: String? = nil,
              bundleID: String? = nil, windowTitle: String? = nil, url: String? = nil,
              priority: TodoPriority? = nil, due: Date? = nil, dueHasTime: Bool = false) {
    self.id = id; self.text = text; self.createdAt = createdAt; self.doneAt = doneAt
    self.appName = appName; self.bundleID = bundleID; self.windowTitle = windowTitle; self.url = url
    self.priority = priority; self.due = due; self.dueHasTime = dueHasTime
  }

  /// Old files lack priority/due/dueHasTime; they decode as nil/nil/false.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    text = try c.decode(String.self, forKey: .text)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
    appName = try c.decodeIfPresent(String.self, forKey: .appName)
    bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
    windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
    url = try c.decodeIfPresent(String.self, forKey: .url)
    priority = try c.decodeIfPresent(TodoPriority.self, forKey: .priority)
    due = try c.decodeIfPresent(Date.self, forKey: .due)
    dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
  }
}

/// The todo list behind the side panel, saved as JSON after every change.
@MainActor
@Observable
public final class TodoStore {
  public private(set) var items: [TodoItem] = []
  private let fileURL: URL
  /// Called with all items after every save; the app syncs reminders from it.
  @ObservationIgnored public var onChange: (@MainActor ([TodoItem]) -> Void)?

  public init(fileURL: URL) {
    self.fileURL = fileURL
    items = Self.load(fileURL)
  }

  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ping-signals/todos.json")
  }

  /// Unfinished: priority high to low (none last), then earliest due (none last), then newest first.
  public var open: [TodoItem] {
    items.filter { !$0.isDone }.sorted { a, b in
      if a.priority != b.priority { return (a.priority?.rawValue ?? 0) > (b.priority?.rawValue ?? 0) }
      if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
      return a.createdAt > b.createdAt
    }
  }
  /// Finished, most recently finished first.
  public var done: [TodoItem] {
    items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
  }

  @discardableResult
  public func add(_ text: String, context: TodoContext, priority: TodoPriority? = nil, due: Date? = nil,
                  dueHasTime: Bool = false, now: Date = Date()) -> TodoItem? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    let item = TodoItem(id: UUID(), text: t, createdAt: now, doneAt: nil, appName: context.appName,
                        bundleID: context.bundleID, windowTitle: context.windowTitle, url: context.url,
                        priority: priority, due: due, dueHasTime: due == nil ? false : dueHasTime)
    items.append(item)
    save()
    return item
  }

  public func toggleDone(_ id: UUID, now: Date = Date()) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].doneAt = items[i].doneAt == nil ? now : nil
    save()
  }

  public func edit(_ id: UUID, text: String) {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].text = t
    save()
  }

  public func setPriority(_ id: UUID, _ p: TodoPriority?) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].priority = p
    save()
  }

  public func setDue(_ id: UUID, _ due: Date?, hasTime: Bool) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].due = due
    items[i].dueHasTime = due == nil ? false : hasTime
    save()
  }

  public func delete(_ id: UUID) {
    items.removeAll { $0.id == id }
    save()
  }

  private func save() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(items) {
      try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: fileURL, options: .atomic)
    }
    onChange?(items)
  }

  /// Decodes item by item: a broken entry is skipped, the rest survive.
  private static func load(_ url: URL) -> [TodoItem] {
    guard let data = try? Data(contentsOf: url),
          let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return array.compactMap { obj in
      guard JSONSerialization.isValidJSONObject(obj), let d = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
      return try? decoder.decode(TodoItem.self, from: d)
    }
  }
}
