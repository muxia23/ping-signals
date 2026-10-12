import Foundation

/// One placed ping. v1 only animates it; later handlers give each ping a meaning (e.g. "?" logs a question).
public struct PingSignal: Equatable, Sendable {
  /// `.preview`: placed from the menu bar to look at it; never triggers an action.
  public enum Source: Equatable, Sendable { case wheel, click, preview }
  public let ping: PingID
  public let style: WheelStyle
  /// Global coordinates (primary screen's top-left origin, y down).
  public let point: GesturePoint
  /// Bundle identifier of the frontmost app when the ping was placed.
  public let frontApp: String?
  public let time: Date
  public let source: Source

  public init(ping: PingID, style: WheelStyle, point: GesturePoint, frontApp: String?, time: Date, source: Source) {
    self.ping = ping; self.style = style; self.point = point; self.frontApp = frontApp; self.time = time; self.source = source
  }
}

/// Handles a signal without throwing: a failing handler must not stop the others.
@MainActor
public protocol SignalHandler: AnyObject {
  func handle(_ signal: PingSignal)
}

@MainActor
public final class SignalBus {
  private var handlers: [SignalHandler] = []

  public init() {}

  public var handlerCount: Int { handlers.count }

  public func register(_ handler: SignalHandler) { handlers.append(handler) }

  /// Calls every handler in registration order, synchronously.
  public func emit(_ signal: PingSignal) {
    for h in handlers { h.handle(signal) }
  }
}
