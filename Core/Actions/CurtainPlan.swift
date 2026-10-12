import CoreGraphics

/// A normal (layer 0) on-screen window, in global coordinates.
public struct OnScreenWindow: Equatable, Sendable {
  public let pid: Int32
  public let bounds: CGRect
  public init(pid: Int32, bounds: CGRect) { self.pid = pid; self.bounds = bounds }
}

/// Retreat can't hide a native-fullscreen window (macOS refuses), so the screens showing one get
/// covered with their wallpaper instead.
public enum CurtainPlan {
  /// Indices into `screens` (global rects) that another app's window fills completely.
  public static func screensToCover(screens: [CGRect], windows: [OnScreenWindow], selfPID: Int32) -> [Int] {
    screens.indices.filter { i in
      windows.contains { w in w.pid != selfPID && fills(w.bounds, screens[i]) }
    }
  }

  private static func fills(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
  }
}
