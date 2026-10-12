import AppKit
import PingCore

/// Runs any ActionConfig. Built-in actions keep their own classes; the generic ones live here.
/// Failures are logged only: an action must never get in the way of the ping itself.
@MainActor
final class ActionRunner {
  private let builtIn: [ActionConfig.Kind: PingAction]

  init(retreat: PingAction, todoPanel: PingAction, claude: PingAction) {
    builtIn = [.retreat: retreat, .todoPanel: todoPanel, .claudeQuickEntry: claude]
  }

  func run(_ config: ActionConfig, signal: PingSignal) {
    guard config.isEffective else { return }
    switch config {
    case .none: return
    case .retreat, .todoPanel, .claudeQuickEntry:
      builtIn[config.kind]?.perform(signal)
    case .keystroke(let h):
      SyntheticInput.whenModifiersReleased { SyntheticInput.press(h) }
    case .open(let s):
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: trimmed), url.scheme != nil else {
        NSLog("ping-signals: not a URL: %@", trimmed)
        return
      }
      NSWorkspace.shared.open(url)
    case .shortcut(let name):
      withContext(signal) { ctx in Self.runShortcut(name, input: ctx.jsonData()) }
    case .shell(let command):
      withContext(signal) { ctx in Self.runShell(command, extraEnv: ctx.environment) }
    }
  }

  private func withContext(_ signal: PingSignal, _ body: @escaping @MainActor (ActionContext) -> Void) {
    Task { @MainActor in
      let front = await ContextCapture.captureWaitingForURL()
      body(ActionContext(signal: signal, front: front))
    }
  }

  private static func runShortcut(_ name: String, input: Data) {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("ping-\(UUID().uuidString).json")
    do { try input.write(to: file) } catch {
      NSLog("ping-signals: shortcut input not written: %@", "\(error)")
      return
    }
    launch("/usr/bin/shortcuts", ["run", name, "--input-path", file.path], env: nil, label: "shortcut \(name)") {
      try? FileManager.default.removeItem(at: file)
    }
  }

  private static func runShell(_ command: String, extraEnv: [String: String]) {
    let env = ProcessInfo.processInfo.environment.merging(extraEnv) { _, new in new }
    launch("/bin/zsh", ["-lc", command], env: env, label: "shell") {}
  }

  /// Starts a background process; never waits for it.
  private static func launch(_ path: String, _ args: [String], env: [String: String]?, label: String,
                             done: @escaping @Sendable () -> Void) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let env { p.environment = env }
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    p.terminationHandler = { proc in
      if proc.terminationStatus != 0 { NSLog("ping-signals: %@ exited with %d", label, proc.terminationStatus) }
      done()
    }
    do { try p.run() } catch {
      NSLog("ping-signals: %@ failed to start: %@", label, "\(error)")
      done()
    }
  }

  /// Names of the user's shortcuts (`shortcuts list`), for the settings picker.
  nonisolated static func listShortcuts() async -> [String] {
    await Task.detached {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
      p.arguments = ["list"]
      let out = Pipe()
      p.standardOutput = out
      p.standardError = FileHandle.nullDevice
      do { try p.run() } catch { return [] }
      let data = out.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }.value
  }
}
