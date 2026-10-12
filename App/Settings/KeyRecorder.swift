import AppKit
import PingCore
import SwiftUI

/// Click, then press a key (combination). Esc cancels. `validate` returns an error message or nil.
struct KeyRecorder: View {
  @Binding var value: Hotkey
  var validate: (Hotkey) -> String? = { _ in nil }
  let setRecording: (Bool) -> Void

  @State private var recording = false
  @State private var monitor: Any?
  @State private var error: String?

  var body: some View {
    HStack(spacing: 8) {
      Button(recording ? String(localized: "Press keys…") : KeyNames.display(value)) {
        recording ? stop() : start()
      }
      .frame(minWidth: 90)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .onDisappear { stop() }
  }

  private func start() {
    error = nil
    recording = true
    setRecording(true)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
      let f = e.modifierFlags
      if e.keyCode == 0x35 && f.intersection([.control, .option, .shift, .command]).isEmpty {  // Esc
        stop()
        return nil
      }
      let vk = KeyMap.keyCodeToVK(e.keyCode)
      guard vk != 0 else { return nil }
      var mods: Mods = []
      if f.contains(.control) { mods.insert(.control) }
      if f.contains(.option) { mods.insert(.option) }
      if f.contains(.shift) { mods.insert(.shift) }
      if f.contains(.command) { mods.insert(.command) }
      let h = Hotkey(mods: mods, vk: vk)
      if let msg = validate(h) { error = msg; return nil }
      value = h
      stop()
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if recording { setRecording(false) }
    recording = false
  }
}
