import AppKit
import PingCore

/// What the user was looking at when a ping fired. Must run before our own panel takes focus.
@MainActor
enum ContextCapture {
  /// App and window title now; the browser URL (if any) arrives later through `onURL`, because
  /// AppleScript can take a moment and asks for Automation permission the first time.
  static func capture(onURL: @escaping @MainActor (String) -> Void) -> TodoContext {
    guard let app = NSWorkspace.shared.frontmostApplication else { return TodoContext() }
    let ctx = TodoContext(appName: app.localizedName, bundleID: app.bundleIdentifier,
                          windowTitle: windowTitle(pid: app.processIdentifier), url: nil)
    if let id = app.bundleIdentifier, let script = urlScript(for: id) {
      Task.detached {
        if let url = runAppleScript(script) { await onURL(url) }
      }
    }
    return ctx
  }

  /// Title of the focused window via the Accessibility API (permission already granted for the event tap).
  private static func windowTitle(pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    // A hung app must not stall the ping: give up on its window title after 0.3 s.
    AXUIElementSetMessagingTimeout(app, 0.3)
    var window: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, "AXFocusedWindow" as CFString, &window) == .success,
          let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
    var title: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXTitle" as CFString, &title) == .success,
          let s = title as? String, !s.isEmpty else { return nil }
    return s
  }

  static func urlScript(for bundleID: String) -> String? {
    switch bundleID {
    case "com.apple.Safari":
      return #"tell application id "com.apple.Safari" to get URL of current tab of front window"#
    case "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser":
      return #"tell application id "\#(bundleID)" to get URL of active tab of front window"#
    default:
      return nil
    }
  }

  /// Runs osascript in a child process (thread-safe, unlike NSAppleScript off the main thread).
  nonisolated private static func runAppleScript(_ source: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", source]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty || s == "missing value" ? nil : s
  }

  /// Like `capture`, but waits (at most `timeout`) for the browser URL so one-shot actions get it too.
  static func captureWaitingForURL(timeout: Duration = .seconds(1)) async -> TodoContext {
    let once = Once()
    return await withCheckedContinuation { (cont: CheckedContinuation<TodoContext, Never>) in
      var ctx = TodoContext()
      ctx = capture { url in
        guard !once.fired else { return }
        once.fired = true
        var withURL = once.base
        withURL.url = url
        cont.resume(returning: withURL)
      }
      once.base = ctx
      guard let id = ctx.bundleID, urlScript(for: id) != nil else {
        once.fired = true
        cont.resume(returning: ctx)
        return
      }
      Task { @MainActor in
        try? await Task.sleep(for: timeout)
        guard !once.fired else { return }
        once.fired = true
        cont.resume(returning: once.base)
      }
    }
  }

  @MainActor private final class Once {
    var fired = false
    var base = TodoContext()
  }
}
