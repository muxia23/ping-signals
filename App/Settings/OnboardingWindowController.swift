import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
  private var window: NSWindow?
  private var closeObserver: NSObjectProtocol?

  func show() {
    if window == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
      w.title = "ping-signals"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      window = w
      // Release it once closed; it's only needed until permission is granted.
      closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                             queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if let o = self.closeObserver { NotificationCenter.default.removeObserver(o) }
          self.closeObserver = nil
          let closing = self.window
          self.window = nil
          DispatchQueue.main.async { _ = closing }
        }
      }
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func close() { window?.close() }
}

struct OnboardingView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
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
