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

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var text: String
  public let createdAt: Date
  public var doneAt: Date?
  public var appName: String?
  public var bundleID: String?
  public var windowTitle: String?
  public var url: String?

  public var isDone: Bool { doneAt != nil }
}

/// The todo list behind the side panel, saved as JSON after every change.
@MainActor
@Observable
public final class TodoStore {
  public private(set) var items: [TodoItem] = []
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    items = Self.load(fileURL)
  }

  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ping-signals/todos.json")
  }

  /// Unfinished, newest first.
  public var open: [TodoItem] { items.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt } }
  /// Finished, most recently finished first.
  public var done: [TodoItem] {
    items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
  }

  @discardableResult
  public func add(_ text: String, context: TodoContext, now: Date = Date()) -> TodoItem? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    let item = TodoItem(id: UUID(), text: t, createdAt: now, doneAt: nil, appName: context.appName,
                        bundleID: context.bundleID, windowTitle: context.windowTitle, url: context.url)
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

  public func delete(_ id: UUID) {
    items.removeAll { $0.id == id }
    save()
  }

  private func save() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(items) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
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
