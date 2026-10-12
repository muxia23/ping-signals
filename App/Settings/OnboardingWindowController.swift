import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
  private var window: NSWindow?

  func show() {
    if window == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
      w.title = "ping-signals"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      window = w
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func close() { window?.close() }
}

struct OnboardingView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 56)).foregroundStyle(.tint)
      Text("Allow ping-signals to see ⌥ + drag").font(.title2.bold())
      Text("ping-signals needs Accessibility access to notice the trigger key and the mouse. It doesn't read what you type and sends nothing anywhere.")
        .multilineTextAlignment(.center).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 6) {
        Text("1. Click “Open System Settings”.")
        Text("2. Turn on ping-signals under Accessibility.")
        Text("3. Come back: this window closes by itself.")
      }
      Button("Open System Settings") { AccessibilityGate.requestAndOpenSettings() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(28)
    .frame(width: 440)
  }
}
