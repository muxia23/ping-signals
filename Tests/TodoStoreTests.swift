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
}
