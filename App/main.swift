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
  }
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
