import QuartzCore
import PingCore

/// Shows a WheelArt at a point and highlights the slice under the pointer. Never redraws: it only
/// toggles which pre-rendered image layers are visible.
@MainActor
final class WheelLayer {
  let root = CALayer()
  private let underLayer = CALayer(), overLayer = CALayer(), hotCenter = CALayer()
  private var highlightLayers: [CALayer] = []
  private var art: WheelArt?
  private var origin = CGPoint.zero
  private(set) var hot: Int?

  init() {
    root.isHidden = true
    root.addSublayer(underLayer)
    root.addSublayer(overLayer)
    root.addSublayer(hotCenter)
  }

  func setArt(_ art: WheelArt) {
    self.art = art
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlightLayers.forEach { $0.removeFromSuperlayer() }
    // Canvas frames are y down; layer geometry here is y up.
    func place(_ l: CALayer, _ f: CGRect) {
      l.frame = CGRect(x: f.minX, y: art.size.height - f.maxY, width: f.width, height: f.height)
      l.contentsScale = art.scale
    }
    highlightLayers = art.highlights.map { img in
      let l = CALayer()
      l.contents = img.image
      l.isHidden = true
      place(l, img.frame)
      return l
    }
    for l in highlightLayers { root.insertSublayer(l, above: underLayer) }
    underLayer.contents = art.under
    overLayer.contents = art.over
    hotCenter.contents = art.centerHot?.image
    root.bounds = CGRect(origin: .zero, size: art.size)
    let canvas = CGRect(origin: .zero, size: art.size)
    place(underLayer, canvas)
    place(overLayer, canvas)
    place(hotCenter, art.centerHot?.frame ?? canvas)
    CATransaction.commit()
  }

  /// `p` in the hosting view's coordinates (AppKit, y up).
  func open(at p: CGPoint) {
    origin = p
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.position = p
    root.isHidden = false
    setHot(nil)
    CATransaction.commit()
  }

  var isOpen: Bool { !root.isHidden }

  /// Returns true when a different slice (not the dead zone) became highlighted.
  @discardableResult
  func move(to p: CGPoint) -> Bool {
    guard !root.isHidden else { return false }
    let slice = pick(p)
    guard slice != hot else { return false }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    setHot(slice)
    CATransaction.commit()
    return slice != nil
  }

  /// Closes the wheel; the chosen slice, or nil in the dead zone.
  func release(at p: CGPoint) -> Int? {
    guard !root.isHidden else { return nil }
    let slice = pick(p)
    close()
    return slice
  }

  func close() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.isHidden = true
    setHot(nil)
    CATransaction.commit()
  }

  /// The wheel centre in the hosting view's coordinates.
  var center: CGPoint { origin }

  private func pick(_ p: CGPoint) -> Int? {
    guard let art else { return nil }
    // View coordinates are y up; pickSlice wants y down.
    return WheelGeometry.pickSlice(dx: Double(p.x - origin.x), dy: Double(origin.y - p.y),
                                   slots: art.slots, deadZone: Double(art.deadZone))
  }

  private func setHot(_ slice: Int?) {
    hot = slice
    for (i, l) in highlightLayers.enumerated() { l.isHidden = i != slice }
    hotCenter.isHidden = slice != nil
  }
}
