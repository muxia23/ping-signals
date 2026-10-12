import AppKit
import QuartzCore
import PingCore

/// The pre-12.22 ping: a tinted base ring flat on the ground, the icon dropping onto it.
/// The game used particle effects we can't read, so this follows their look rather than their numbers.
@MainActor
enum ClassicPingAnimator {
  /// Ground-plane squash for the base rings.
  static let groundSquash: CGFloat = 0.45
  /// Icon pixels → points: an icon 128 px wide is 0.55 × size wide.
  static let iconScale: CGFloat = 0.55 / 128

  static func spawn(_ def: PingDef, at p: CGPoint, size s: CGFloat, duration dur: CFTimeInterval, in parent: CALayer) -> CALayer {
    let root = CALayer()
    root.position = p
    root.bounds = .zero
    let fadeIn = 0.2 / dur

    for (i, name) in def.base.enumerated() {
      let base = CALayer()
      base.contents = Textures.tinted(name, def.color)
      let d = i == 0 ? s : 1.3 * s
      base.bounds = CGRect(x: 0, y: 0, width: d, height: d * groundSquash)
      base.position = .zero
      base.opacity = 0
      if i == 0 {
        let sc = CABasicAnimation(keyPath: "transform.scale")
        sc.fromValue = 0.6
        sc.toValue = 1
        sc.duration = 0.2
        sc.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let op = ModernPingAnimator.keyframes("opacity", [0, 1, 1, 0], [0, fadeIn, 0.85, 1], dur)
        let g = CAAnimationGroup()
        g.animations = [sc, op]
        g.duration = dur
        base.add(g, forKey: "base")
      } else {
        // Enemy Missing's outer ring: grows and fades once.
        let sc = CABasicAnimation(keyPath: "transform.scale")
        sc.fromValue = 0.8
        sc.toValue = 1.4
        let op = ModernPingAnimator.keyframes("opacity", [0, 0.8, 0], [0, 0.2, 1], 1.2)
        let g = CAAnimationGroup()
        g.animations = [sc, op]
        g.duration = 1.2
        base.add(g, forKey: "outer")
      }
      root.addSublayer(base)
    }

    guard let name = def.art.first, let img = Textures.named(name) else {
      parent.addSublayer(root)
      return root
    }
    let w = CGFloat(img.width) * iconScale * s, h = CGFloat(img.height) * iconScale * s
    let life = CALayer()
    life.bounds = CGRect(x: 0, y: 0, width: w, height: h)
    life.anchorPoint = CGPoint(x: 0.5, y: 0)           // bottom centre sits on the base
    life.position = .zero
    life.opacity = 0
    life.add(ModernPingAnimator.keyframes("opacity", [0, 1, 1, 0], [0, fadeIn, 0.85, 1], dur), forKey: "life")
    root.addSublayer(life)

    let icon = CALayer()
    icon.contents = img
    icon.frame = life.bounds
    life.addSublayer(icon)
    let drop = CAKeyframeAnimation(keyPath: "transform.translation.y")
    drop.values = [0.3 * s, -0.04 * s, 0]
    drop.keyTimes = [0, 0.7, 1]
    drop.duration = 0.25
    drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
    icon.add(drop, forKey: "drop")
    let bob = CABasicAnimation(keyPath: "transform.translation.y")
    bob.fromValue = 0
    bob.toValue = 4
    bob.duration = 0.8
    bob.autoreverses = true
    bob.repeatCount = .infinity
    bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    bob.beginTime = CACurrentMediaTime() + 0.3
    icon.add(bob, forKey: "bob")

    parent.addSublayer(root)
    return root
  }
}
