import CoreGraphics

/// Global coordinates (CGEvent, CGWindowList): origin at the primary screen's top-left, y down.
/// AppKit coordinates (NSScreen, NSWindow): origin at the primary screen's bottom-left, y up.
public enum ScreenMath {
  public static func appKitPoint(fromGlobal p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: p.x, y: primaryHeight - p.y)
  }

  public static func globalPoint(fromAppKit p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: p.x, y: primaryHeight - p.y)
  }

  /// A global point in the coordinate space of a window covering `screenFrame` (AppKit, y up).
  public static func localPoint(fromGlobal p: CGPoint, screenFrame: CGRect, primaryHeight: CGFloat) -> CGPoint {
    let a = appKitPoint(fromGlobal: p, primaryHeight: primaryHeight)
    return CGPoint(x: a.x - screenFrame.minX, y: a.y - screenFrame.minY)
  }

  public static func globalRect(ofScreenFrame f: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
  }
}
