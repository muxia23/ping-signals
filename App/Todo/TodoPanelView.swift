import AppKit
import SwiftUI
import PingCore

/// The text being typed, the priority and DDL picked for it, and the context it will be saved with.
@MainActor
@Observable
final class TodoDraft {
  var text = ""
  var priority: TodoPriority?
  var due: Date?
  var dueHasTime = false
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
  @State private var hovered: UUID?
  @State private var draftPopover: DraftPopover?

  private enum DraftPopover { case priority, due }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      inputCard
      TimelineView(.everyMinute) { context in
        if store.open.isEmpty && store.done.isEmpty {
          emptyState
        } else {
          list(now: context.date)
        }
      }
    }
    .padding(16)
    .frame(width: TodoPanelController.width)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { inputFocused = true }
    .onChange(of: draft.focusToken) { inputFocused = true }
    .onExitCommand(perform: onClose)
  }

  // MARK: Header and input

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "checklist").font(.title3).foregroundStyle(.tint)
      Text("Todo").font(.title3.bold())
      if !store.open.isEmpty {
        Text("\(store.open.count)")
          .font(.caption.bold().monospacedDigit())
          .padding(.horizontal, 7).padding(.vertical, 2)
          .background(Capsule().fill(Color.accentColor.opacity(0.18)))
          .foregroundStyle(.tint)
      }
      Spacer()
      Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title3) }
        .buttonStyle(.plain).foregroundStyle(.tertiary)
    }
  }

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Write something… (Return to save)", text: $draft.text)
        .textFieldStyle(.plain)
        .font(.body)
        .focused($inputFocused)
        .onSubmit(save)
      HStack(spacing: 6) {
        Chip(icon: "flag.fill", text: draft.priority.map(TodoStyle.name) ?? String(localized: "Priority"),
             tint: draft.priority.map(TodoStyle.color), active: draft.priority != nil,
             onClear: { draft.priority = nil }) { draftPopover = .priority }
          .popover(isPresented: Binding(get: { draftPopover == .priority }, set: { if !$0 { draftPopover = nil } })) {
            PriorityPicker(selection: draft.priority) { draft.priority = $0; draftPopover = nil }
          }
        Chip(icon: "calendar",
             text: draft.due.map { TodoStyle.dueText($0, hasTime: draft.dueHasTime, now: Date()) } ?? String(localized: "Due"),
             tint: draft.due.map { TodoStyle.dueColor($0, hasTime: draft.dueHasTime, now: Date()) }, active: draft.due != nil,
             onClear: { draft.due = nil; draft.dueHasTime = false }) { draftPopover = .due }
          .popover(isPresented: Binding(get: { draftPopover == .due }, set: { if !$0 { draftPopover = nil } })) {
            DueEditor(due: draft.due, hasTime: draft.dueHasTime) { due, hasTime in
              draft.due = due
              draft.dueHasTime = hasTime
              draftPopover = nil
            }
          }
        Spacer(minLength: 4)
        if let source = Self.sourceLabel(appName: draft.context.appName, title: draft.context.windowTitle, url: draft.context.url) {
          Label(source, systemImage: "link")
            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
  }

  /// Quick syntax in the text (`!高 @明天18:00`) wins over the chips.
  private func save() {
    let parsed = TodoQuickParse.parse(draft.text, now: Date())
    let due = parsed.due ?? draft.due
    let hasTime = parsed.due != nil ? parsed.dueHasTime : draft.dueHasTime
    if store.add(parsed.text, context: draft.context, priority: parsed.priority ?? draft.priority,
                 due: due, dueHasTime: due != nil && hasTime) != nil {
      draft.text = ""
      draft.priority = nil
      draft.due = nil
      draft.dueHasTime = false
    }
    inputFocused = true
  }

  // MARK: List

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "checkmark.seal").font(.system(size: 36)).foregroundStyle(.tint.opacity(0.7))
      Text("All clear").font(.headline)
      Text("Type above and press Return. Try “Send report !high @fri”.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 40)
  }

  private func list(now: Date) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        ForEach(store.open) { row($0, now: now) }
        if !store.done.isEmpty {
          DisclosureGroup("Done (\(store.done.count))", isExpanded: $showDone) {
            VStack(spacing: 8) { ForEach(store.done) { row($0, now: now) } }.padding(.top, 6)
          }
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
        }
      }
    }
    .scrollIndicators(.never)
  }

  @ViewBuilder
  private func row(_ item: TodoItem, now: Date) -> some View {
    TodoRow(item: item, now: now, hovered: hovered == item.id, editing: editing == item.id, editText: $editText,
            store: store, onOpenSource: onOpenSource,
            onStartEdit: { editing = item.id; editText = item.text },
            onEndEdit: { editing = nil })
      .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
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

// MARK: - Row

private struct TodoRow: View {
  let item: TodoItem
  let now: Date
  let hovered: Bool
  let editing: Bool
  @Binding var editText: String
  let store: TodoStore
  let onOpenSource: (TodoItem) -> Void
  let onStartEdit: () -> Void
  let onEndEdit: () -> Void

  @State private var popover: Popover?
  private enum Popover: Identifiable {
    case priority, due
    var id: Self { self }
  }

  private var tint: Color? { item.isDone ? nil : item.priority.map(TodoStyle.color) }

  var body: some View {
    HStack(spacing: 0) {
      RoundedRectangle(cornerRadius: 2)
        .fill(tint ?? .clear)
        .frame(width: 3)
        .padding(.vertical, 8)
      HStack(alignment: .top, spacing: 10) {
        Button { store.toggleDone(item.id) } label: {
          Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 17))
            .foregroundStyle(item.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint ?? .secondary))
        }
        .buttonStyle(.plain)
        .padding(.top, 1)

        VStack(alignment: .leading, spacing: 5) {
          if editing {
            TextField("", text: $editText)
              .textFieldStyle(.roundedBorder)
              .onSubmit { store.edit(item.id, text: editText); onEndEdit() }
              .onExitCommand(perform: onEndEdit)
          } else {
            Text(item.text)
              .strikethrough(item.isDone)
              .foregroundStyle(item.isDone ? .secondary : .primary)
              .fixedSize(horizontal: false, vertical: true)
              .onTapGesture(count: 2, perform: onStartEdit)
          }
          meta
        }
        Spacer(minLength: 0)
        if hovered && !editing { actions }
      }
      .padding(.vertical, 10)
      .padding(.leading, 8)
      .padding(.trailing, 10)
    }
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovered ? 0.08 : 0.045)))
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .animation(.easeOut(duration: 0.12), value: hovered)
    .contextMenu { contextMenu }
    .popover(item: $popover) { which in
      switch which {
      case .priority:
        PriorityPicker(selection: item.priority) { store.setPriority(item.id, $0); popover = nil }
      case .due:
        DueEditor(due: item.due, hasTime: item.dueHasTime) { store.setDue(item.id, $0, hasTime: $1); popover = nil }
      }
    }
  }

  private var meta: some View {
    HStack(spacing: 6) {
      if let due = item.due, !item.isDone {
        let color = TodoStyle.dueColor(due, hasTime: item.dueHasTime, now: now)
        Label(TodoStyle.dueText(due, hasTime: item.dueHasTime, now: now), systemImage: "calendar")
          .font(.caption.weight(.medium))
          .padding(.horizontal, 6).padding(.vertical, 2)
          .background(Capsule().fill(color.opacity(0.14)))
          .foregroundStyle(color)
      }
      if let source = TodoPanelView.sourceLabel(appName: item.appName, title: item.windowTitle, url: item.url) {
        Button { onOpenSource(item) } label: {
          Label(source, systemImage: item.url != nil ? "safari" : "macwindow").lineLimit(1).truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
      }
      Text(item.createdAt.formatted(.relative(presentation: .named)))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
    .font(.caption)
  }

  private var actions: some View {
    HStack(spacing: 2) {
      if !item.isDone {
        iconButton("flag", help: "Priority") { popover = .priority }
        iconButton("calendar", help: "Due") { popover = .due }
      }
      iconButton("trash", help: "Delete") { store.delete(item.id) }
    }
    .transition(.opacity)
  }

  private func iconButton(_ symbol: String, help: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 22) }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help(help)
  }

  @ViewBuilder
  private var contextMenu: some View {
    if !item.isDone {
      Menu("Priority") {
        ForEach(TodoPriority.allCases.reversed(), id: \.self) { p in
          Button(TodoStyle.name(p)) { store.setPriority(item.id, p) }
        }
        Divider()
        Button("No Priority") { store.setPriority(item.id, nil) }
      }
      Menu("Due") {
        ForEach(TodoStyle.quickDates(now: Date()), id: \.title) { q in
          Button(q.title) { store.setDue(item.id, q.date, hasTime: false) }
        }
        Divider()
        Button("No Due Date") { store.setDue(item.id, nil, hasTime: false) }
      }
      Divider()
    }
    Button("Edit", action: onStartEdit)
    Button("Delete", role: .destructive) { store.delete(item.id) }
  }
}

// MARK: - Pieces

/// A small capsule button for the input card: grey when unset, tinted with a clear button when set.
private struct Chip: View {
  let icon: String
  let text: String
  let tint: Color?
  let active: Bool
  let onClear: () -> Void
  let action: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Button(action: action) {
        Label(text, systemImage: icon).lineLimit(1)
      }
      .buttonStyle(.plain)
      if active {
        Button(action: onClear) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
          .buttonStyle(.plain)
      }
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(Capsule().fill((active ? tint ?? .accentColor : Color.primary).opacity(active ? 0.16 : 0.06)))
    .foregroundStyle(active ? AnyShapeStyle(tint ?? .accentColor) : AnyShapeStyle(.secondary))
  }
}

struct PriorityPicker: View {
  let selection: TodoPriority?
  let onPick: (TodoPriority?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(TodoPriority.allCases.reversed(), id: \.self) { p in
        option(TodoStyle.name(p), color: TodoStyle.color(p), selected: selection == p) { onPick(p) }
      }
      Divider().padding(.vertical, 2)
      option(String(localized: "No Priority"), color: .secondary, selected: selection == nil) { onPick(nil) }
    }
    .padding(8)
    .frame(width: 170)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func option(_ title: String, color: Color, selected: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        Image(systemName: "flag.fill").foregroundStyle(color)
        Text(title)
        Spacer()
        if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
      }
      .padding(.horizontal, 8).padding(.vertical, 5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Quick dates, a calendar and an optional time.
struct DueEditor: View {
  let onSet: (Date?, Bool) -> Void
  @State private var day: Date
  @State private var withTime: Bool
  @State private var time: Date

  private static let presetHours = [9, 12, 18, 21]

  init(due: Date?, hasTime: Bool, onSet: @escaping (Date?, Bool) -> Void) {
    self.onSet = onSet
    let base = due ?? Calendar.current.startOfDay(for: Date())
    _day = State(initialValue: base)
    _withTime = State(initialValue: due != nil && hasTime)
    _time = State(initialValue: hasTime ? base : Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: base) ?? base)
  }

  var body: some View {
    let cal = Calendar.current
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        ForEach(TodoStyle.quickDates(now: Date()), id: \.title) { q in
          TodoPill(title: q.title, selected: cal.isDate(day, inSameDayAs: q.date)) { day = q.date }
        }
      }
      DatePicker("", selection: $day, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .labelsHidden()
        .focusEffectDisabled()
        .frame(maxWidth: .infinity)
      Divider()
      HStack(spacing: 8) {
        Label("Time", systemImage: "clock").foregroundStyle(.secondary)
        Spacer()
        if withTime {
          DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
            .labelsHidden()
            .focusEffectDisabled()
            .fixedSize()
          Button { withTime = false } label: { Image(systemName: "xmark.circle.fill") }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        } else {
          Button("Add Time") { withTime = true }.buttonStyle(.plain).foregroundStyle(.tint)
        }
      }
      .font(.callout)
      if withTime {
        HStack(spacing: 6) {
          ForEach(Self.presetHours, id: \.self) { h in
            TodoPill(title: String(format: "%02d:00", h),
                     selected: cal.component(.hour, from: time) == h && cal.component(.minute, from: time) == 0) {
              time = cal.date(bySettingHour: h, minute: 0, second: 0, of: time) ?? time
            }
          }
        }
      }
      HStack {
        Button("Clear") { onSet(nil, false) }.buttonStyle(.plain).foregroundStyle(.secondary)
        Spacer()
        Button("Done", action: commit)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
      .font(.callout)
    }
    .padding(14)
    .frame(width: 256)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func commit() {
    let cal = Calendar.current
    let start = cal.startOfDay(for: day)
    guard withTime else { onSet(start, false); return }
    let hm = cal.dateComponents([.hour, .minute], from: time)
    onSet(cal.date(bySettingHour: hm.hour ?? 18, minute: hm.minute ?? 0, second: 0, of: start) ?? start, true)
  }
}

/// A small capsule choice: filled with the accent colour when selected.
private struct TodoPill: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.caption.weight(.medium).monospacedDigit())
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Style

@MainActor
enum TodoStyle {
  static func name(_ p: TodoPriority) -> String {
    switch p {
    case .high: String(localized: "High")
    case .medium: String(localized: "Medium")
    case .low: String(localized: "Low")
    }
  }

  static func color(_ p: TodoPriority) -> Color {
    switch p {
    case .high: .red
    case .medium: .orange
    case .low: .blue
    }
  }

  /// "Overdue 2 days", "Today 18:00", "Tomorrow", "Oct 20 18:00".
  static func dueText(_ due: Date, hasTime: Bool, now: Date) -> String {
    let time = hasTime ? " " + due.formatted(date: .omitted, time: .shortened) : ""
    switch TodoDue.status(due: due, hasTime: hasTime, now: now) {
    case .overdue(let days):
      return days == 0 ? String(localized: "Overdue") + time : String(localized: "Overdue \(days) days")
    case .today: return String(localized: "Today") + time
    case .tomorrow: return String(localized: "Tomorrow") + time
    case .later: return due.formatted(.dateTime.month(.abbreviated).day()) + time
    }
  }

  static func dueColor(_ due: Date, hasTime: Bool, now: Date) -> Color {
    switch TodoDue.status(due: due, hasTime: hasTime, now: now) {
    case .overdue: .red
    case .today: .orange
    case .tomorrow, .later: .secondary
    }
  }

  struct QuickDate { let title: String; let date: Date }

  /// Today, tomorrow and next Monday, as start-of-day dates.
  static func quickDates(now: Date) -> [QuickDate] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
    let monday = cal.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? today
    return [QuickDate(title: String(localized: "Today"), date: today),
            QuickDate(title: String(localized: "Tomorrow"), date: tomorrow),
            QuickDate(title: String(localized: "Next Monday"), date: monday)]
  }
}
