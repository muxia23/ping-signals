import Foundation

/// What a shortcut or shell action is told about the ping: as environment variables or as JSON input.
public struct ActionContext: Equatable, Sendable {
  public let signal: PingSignal
  public let front: TodoContext

  public init(signal: PingSignal, front: TodoContext) {
    self.signal = signal
    self.front = front
  }

  private var fields: [(env: String, json: String, value: Any?)] {
    [("PING_ID", "ping", signal.ping.rawValue), ("PING_STYLE", "style", signal.style.rawValue),
     ("PING_X", "x", signal.point.x), ("PING_Y", "y", signal.point.y),
     ("FRONT_APP", "app", front.appName), ("FRONT_BUNDLE_ID", "bundleID", front.bundleID),
     ("WINDOW_TITLE", "windowTitle", front.windowTitle), ("FRONT_URL", "url", front.url)]
  }

  /// Variables added to a shell action's environment; absent values are not set.
  public var environment: [String: String] {
    var env: [String: String] = [:]
    for f in fields { if let v = f.value { env[f.env] = "\(v)" } }
    return env
  }

  /// Input for a shortcut: a JSON object, absent values left out.
  public func jsonData() -> Data {
    var obj: [String: Any] = [:]
    for f in fields { if let v = f.value { obj[f.json] = v } }
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
  }
}
