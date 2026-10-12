import AppKit
import SwiftUI
import PingCore

/// The text being typed and the context it will be saved with.
@MainActor
@Observable
final class TodoDraft {
  var text = ""
  var context = TodoContext()
  /// Bumped every time the panel is summoned, to put the focus back in the text field.
  var focusToken = 0
}

struct TodoPanelView: View {
  @Bindable var draft: TodoDraft
  let store: TodoStore
  let onClose: () -> Void
  let onOpenSource: (TodoItem) -> Void

  @FocusState private var inputFocused: Bool
  @State private var showDone = false
  @State private var editing: UUID?
  @State private var editText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Todo").font(.headline)
        Spacer()
        Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
      }
      TextField("Write something… (Return to save)", text: $draft.text)
        .textFieldStyle(.roundedBorder)
        .focused($inputFocused)
        .onSubmit {
          if store.add(draft.text, context: draft.context) != nil { draft.text = "" }
          inputFocused = true
        }
      if let source = Self.sourceLabel(appName: draft.context.appName, title: draft.context.windowTitle, url: draft.context.url) {
        Label(source, systemImage: "link").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(store.open) { row($0) }
          if !store.done.isEmpty {
            DisclosureGroup("Done (\(store.done.count))", isExpanded: $showDone) {
              ForEach(store.done) { row($0) }
            }
            .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(14)
    .frame(width: 360)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { inputFocused = true }
    .onChange(of: draft.focusToken) { inputFocused = true }
    .onExitCommand(perform: onClose)
  }

  @ViewBuilder
  private func row(_ item: TodoItem) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Button { store.toggleDone(item.id) } label: {
        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
      }
      .buttonStyle(.plain)
      VStack(alignment: .leading, spacing: 2) {
        if editing == item.id {
          TextField("", text: $editText)
            .textFieldStyle(.roundedBorder)
            .onSubmit { store.edit(item.id, text: editText); editing = nil }
            .onExitCommand { editing = nil }
        } else {
          Text(item.text)
            .strikethrough(item.isDone)
            .foregroundStyle(item.isDone ? .secondary : .primary)
            .onTapGesture(count: 2) { editing = item.id; editText = item.text }
        }
        HStack(spacing: 6) {
          if let source = Self.sourceLabel(appName: item.appName, title: item.windowTitle, url: item.url) {
            Button(source) { onOpenSource(item) }.buttonStyle(.link).lineLimit(1)
          }
          Text(item.createdAt.formatted(.relative(presentation: .named)))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
    .contextMenu {
      Button("Edit") { editing = item.id; editText = item.text }
      Button("Delete", role: .destructive) { store.delete(item.id) }
    }
  }

  /// "example.com" for a page, "Window title — App" otherwise.
  static func sourceLabel(appName: String?, title: String?, url: String?) -> String? {
    if let url, let host = URL(string: url)?.host() { return host }
    switch (title, appName) {
    case let (t?, a?): return "\(t) — \(a)"
    case let (t?, nil): return t
    case let (nil, a?): return a
    default: return nil
    }
  }
}
