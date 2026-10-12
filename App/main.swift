import AppKit
import PingCore

// `ping-signals --render-wheels <dir>` writes wheel previews as PNGs and exits.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-wheels"), i + 1 < args.count {
  let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  MainActor.assumeIsolated {
    let classic = ClassicWheelRenderer.render(wheel: PingCatalog.classicWheel, pixelScale: 2)
    try? classic.writePreview(to: dir.appendingPathComponent("classic.png"))
    let modern = ModernWheelRenderer.render(wheel: PingCatalog.defaultModernWheel, pixelScale: 2)
    try? modern.writePreview(to: dir.appendingPathComponent("modern.png"))
  }
  exit(0)
}

// Language preference applies from launch (AppKit reads AppleLanguages once).
switch SettingsStore().load().language {
case .auto: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
case .zhHans: UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
