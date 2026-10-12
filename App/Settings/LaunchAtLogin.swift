import ServiceManagement

@MainActor
enum LaunchAtLogin {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func set(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      NSLog("ping-signals: launch at login %@ failed: %@", on ? "register" : "unregister", "\(error)")
    }
  }
}
