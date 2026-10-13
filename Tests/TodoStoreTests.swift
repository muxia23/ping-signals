import Foundation
import Testing
@testable import PingCore

@MainActor
@Suite struct TodoStoreTests {
  private let dir = FileManager.default.temporaryDirectory.appendingPathComponent("todo-tests-\(UUID().uuidString)")
  private var file: URL { dir.appendingPathComponent("todos.json") }
  private let ctx = TodoContext(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Paper", url: "https://example.com/a")
  private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

  @Test func addTrimsAndRejectsEmpty() {
    let s = TodoStore(fileURL: file)
    #expect(s.add("   ", context: ctx, now: t(1)) == nil)
    let item = s.add("  read section 3  ", context: ctx, now: t(1))
    #expect(item?.text == "read section 3")
    #expect(item?.url == "https://example.com/a" && item?.windowTitle == "Paper" && item?.appName == "Safari")
    #expect(s.items.count == 1)
  }

  @Test func openNewestFirstAndDoneSeparately() {
    let s = TodoStore(fileURL: file)
    let a = s.add("a", context: ctx, now: t(1))!
    _ = s.add("b", context: ctx, now: t(2))
    let c = s.add("c", context: ctx, now: t(3))!
    s.toggleDone(a.id, now: t(10))
    s.toggleDone(c.id, now: t(11))
    #expect(s.open.map(\.text) == ["b"])
    #expect(s.done.map(\.text) == ["c", "a"])   // most recently finished first
    s.toggleDone(c.id, now: t(12))               // un-finish
    #expect(s.open.map(\.text) == ["c", "b"])
  }

  @Test func editAndDelete() {
    let s = TodoStore(fileURL: file)
    let a = s.add("a", context: ctx, now: t(1))!
    s.edit(a.id, text: "  A2 ")
    #expect(s.items.first?.text == "A2")
    s.edit(a.id, text: "   ")                    // empty edit is ignored
    #expect(s.items.first?.text == "A2")
    s.delete(a.id)
    #expect(s.items.isEmpty)
  }

  @Test func persistsAcrossInstances() {
    let s = TodoStore(fileURL: file)
    let a = s.add("keep me", context: ctx, now: t(100))!
    s.toggleDone(a.id, now: t(200))
    let back = TodoStore(fileURL: file)
    #expect(back.items == s.items)
    #expect(back.items.first?.doneAt == t(200))
  }

  @Test func badEntriesAreSkippedNotFatal() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = """
    [{"id":"\(UUID().uuidString)","text":"good","createdAt":"1970-01-01T00:00:05Z"},
     {"text":"no id"},
     42]
    """
    try Data(json.utf8).write(to: file)
    let s = TodoStore(fileURL: file)
    #expect(s.items.map(\.text) == ["good"])
  }

  @Test func missingFileIsEmpty() {
    #expect(TodoStore(fileURL: file).items.isEmpty)
  }

  // MARK: priority / DDL

  @Test func oldJSONWithoutNewKeysLoadsUnchanged() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = """
    [{"id":"\(UUID().uuidString)","text":"old","createdAt":"1970-01-01T00:00:05Z"}]
    """
    try Data(json.utf8).write(to: file)
    let item = TodoStore(fileURL: file).items[0]
    #expect(item.priority == nil && item.due == nil && item.dueHasTime == false)
  }

  @Test func newFieldsRoundTrip() {
    let s = TodoStore(fileURL: file)
    s.add("x", context: ctx, priority: .high, due: t(5000), dueHasTime: true, now: t(1))
    let back = TodoStore(fileURL: file)
    #expect(back.items == s.items)
    #expect(back.items[0].priority == .high && back.items[0].due == t(5000) && back.items[0].dueHasTime)
  }

  @Test func openSortsByPriorityThenDueThenNewest() {
    let s = TodoStore(fileURL: file)
    s.add("none-old", context: ctx, now: t(1))
    s.add("low", context: ctx, priority: .low, now: t(2))
    s.add("med", context: ctx, priority: .medium, now: t(3))
    s.add("high-late", context: ctx, priority: .high, due: t(900), now: t(4))
    s.add("high-early", context: ctx, priority: .high, due: t(100), now: t(5))
    s.add("high-nodue-a", context: ctx, priority: .high, now: t(6))
    s.add("high-nodue-b", context: ctx, priority: .high, now: t(7))
    s.add("none-new", context: ctx, now: t(8))
    #expect(s.open.map(\.text) == ["high-early", "high-late", "high-nodue-b", "high-nodue-a",
                                   "med", "low", "none-new", "none-old"])
  }

  @Test func setPriorityAndDuePersistAndNotify() {
    let s = TodoStore(fileURL: file)
    var calls: [Int] = []
    s.onChange = { calls.append($0.count) }
    let a = s.add("a", context: ctx, now: t(1))!
    s.setPriority(a.id, .medium)
    s.setDue(a.id, t(777), hasTime: true)
    #expect(calls == [1, 1, 1])
    var back = TodoStore(fileURL: file).items[0]
    #expect(back.priority == .medium && back.due == t(777) && back.dueHasTime)
    s.setDue(a.id, nil, hasTime: true)
    s.setPriority(a.id, nil)
    back = TodoStore(fileURL: file).items[0]
    #expect(back.priority == nil && back.due == nil && back.dueHasTime == false)
    s.toggleDone(a.id); s.edit(a.id, text: "b"); s.delete(a.id)
    #expect(calls.count == 8)
  }
}
