import AppKit
import QuartzCore
import PingCore

/// League's current ping effect, after lolPing's overlay.css.
@MainActor
enum ModernPingAnimator {
  /// `scale`: the panel screen's backingScaleFactor, applied to every layer created.
  static func spawn(_ def: PingDef, at p: CGPoint, size s: CGFloat, duration dur: CFTimeInterval,
                    scale: CGFloat, in parent: CALayer) -> CALayer {
    let color = Drawing.color(def.color)
    let root = CALayer()
    root.position = p
    root.bounds = .zero

    // Ground glow: an ellipse under the ping.
    let ground = CAGradientLayer()
    ground.type = .radial
    ground.colors = [color, Drawing.color(def.color, alpha: 0)]
    ground.startPoint = CGPoint(x: 0.5, y: 0.5)
    ground.endPoint = CGPoint(x: 1, y: 1)
    ground.bounds = CGRect(x: 0, y: 0, width: 0.84 * s, height: 0.24 * s)
    ground.position = CGPoint(x: 0, y: -0.32 * s)
    ground.opacity = 0
    ground.add(keyframes("opacity", [0, 0.75, 0.55, 0], [0, 0.1, 0.85, 1], dur), forKey: "ground")
    root.addSublayer(ground)

    // Three rings bursting outward.
    for delay in [0.0, 0.22, 1.4] {
      let ring = CALayer()
      ring.bounds = CGRect(x: 0, y: 0, width: 1.09 * s, height: 1.09 * s)
      ring.cornerRadius = 0.545 * s
      ring.borderWidth = 3
      ring.borderColor = color
      ring.shadowColor = color
      ring.shadowOpacity = 1
      ring.shadowRadius = 9
      ring.shadowOffset = .zero
      ring.opacity = 0
      let scale = CABasicAnimation(keyPath: "transform.scale")
      scale.fromValue = 0.25
      scale.toValue = 1.35
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.95
      fade.toValue = 0
      let g = CAAnimationGroup()
      g.animations = [scale, fade]
      g.duration = 0.65
      g.beginTime = CACurrentMediaTime() + delay
      g.timingFunction = CAMediaTimingFunction(name: .easeOut)
      ring.add(g, forKey: "ring")
      root.addSublayer(ring)
    }

    // The art: pops in, bobs, fades in the last 13 %.
    let art = CALayer()
    art.bounds = CGRect(x: 0, y: 0, width: s, height: s)
    art.position = CGPoint(x: 0, y: 0.23 * s)
    art.add(keyframes("opacity", [1, 1, 0], [0, 0.87, 1], dur), forKey: "life")
    art.opacity = 0   // model value after the animation ends
    root.addSublayer(art)

    let bob = CALayer()
    bob.frame = art.bounds
    art.addSublayer(bob)
    let bobAnim = CABasicAnimation(keyPath: "transform.translation.y")
    bobAnim.fromValue = 0
    bobAnim.toValue = 5
    bobAnim.duration = 0.8
    bobAnim.autoreverses = true
    bobAnim.repeatCount = .infinity
    bobAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    bobAnim.beginTime = CACurrentMediaTime() + (def.art.count == 2 ? 0.5 : 0.3)
    bob.add(bobAnim, forKey: "bob")

    func image(_ name: String) -> CALayer {
      let l = CALayer()
      l.contents = Textures.named(name)
      l.contentsGravity = .resizeAspect
      l.frame = CGRect(x: 0, y: 0, width: s, height: s)
      l.shadowColor = color
      l.shadowOpacity = 1
      l.shadowRadius = 10
      l.shadowOffset = .zero
      return l
    }

    if def.art.count == 2 {
      // All In: two halves slide in and clash, a flash, a shake.
      let clash = CALayer()
      clash.frame = bob.bounds
      bob.addSublayer(clash)
      let a1 = image(def.art[0]), a2 = image(def.art[1])
      clash.addSublayer(a1)
      clash.addSublayer(a2)
      a1.add(slide(from: CGPoint(x: 0.64 * s, y: 0.64 * s)), forKey: "slide")
      a2.add(slide(from: CGPoint(x: -0.64 * s, y: 0.64 * s)), forKey: "slide")
      let shake = CAKeyframeAnimation(keyPath: "transform.translation")
      shake.values = [CGSize.zero, CGSize(width: -3, height: -2), CGSize(width: 3, height: 2), CGSize(width: -2, height: 1), CGSize.zero]
        .map { NSValue(size: $0) }
      shake.duration = 0.25
      shake.beginTime = CACurrentMediaTime() + 0.22
      clash.add(shake, forKey: "shake")
      let flash = CAGradientLayer()
      flash.type = .radial
      flash.colors = [CGColor(gray: 1, alpha: 1), color, Drawing.color(def.color, alpha: 0)]
      flash.locations = [0, 0.4, 1]
      flash.startPoint = CGPoint(x: 0.5, y: 0.5)
      flash.endPoint = CGPoint(x: 1, y: 1)
      flash.frame = CGRect(x: 0.25 * s, y: 0.25 * s, width: 0.5 * s, height: 0.5 * s)
      flash.opacity = 0
      let fs = CABasicAnimation(keyPath: "transform.scale")
      fs.fromValue = 0.3
      fs.toValue = 2.2
      let fo = CAKeyframeAnimation(keyPath: "opacity")
      fo.values = [0, 1, 0]
      fo.keyTimes = [0, 0.3, 1]
      let fg = CAAnimationGroup()
      fg.animations = [fs, fo]
      fg.duration = 0.35
      fg.beginTime = CACurrentMediaTime() + 0.2
      fg.timingFunction = CAMediaTimingFunction(name: .easeOut)
      flash.add(fg, forKey: "flash")
      bob.addSublayer(flash)
    } else {
      let pop = image(def.art[0])
      bob.addSublayer(pop)
      let ps = CAKeyframeAnimation(keyPath: "transform.scale")
      ps.values = [0.4, 1.15, 1]
      ps.keyTimes = [0, 0.6, 1]
      ps.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.2, 1.6, 0.4, 1), CAMediaTimingFunction(controlPoints: 0.2, 1.6, 0.4, 1)]
      let po = CAKeyframeAnimation(keyPath: "opacity")
      po.values = [0, 1, 1]
      po.keyTimes = [0, 0.6, 1]
      let pg = CAAnimationGroup()
      pg.animations = [ps, po]
      pg.duration = 0.28
      pop.add(pg, forKey: "pop")
    }

    setContentsScale(scale, root)
    parent.addSublayer(root)
    return root
  }

  /// Sets `contentsScale` on `layer` and everything below it.
  static func setContentsScale(_ scale: CGFloat, _ layer: CALayer) {
    layer.contentsScale = scale
    layer.sublayers?.forEach { setContentsScale(scale, $0) }
  }

  static func keyframes(_ path: String, _ values: [Double], _ times: [Double], _ dur: CFTimeInterval) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: path)
    a.values = values
    a.keyTimes = times.map { NSNumber(value: $0) }
    a.duration = dur
    return a
  }

  private static func slide(from offset: CGPoint) -> CAAnimation {
    let t = CABasicAnimation(keyPath: "transform.translation")
    t.fromValue = NSValue(size: CGSize(width: offset.x, height: offset.y))
    t.toValue = NSValue(size: .zero)
    let o = CABasicAnimation(keyPath: "opacity")
    o.fromValue = 0
    o.toValue = 1
    let g = CAAnimationGroup()
    g.animations = [t, o]
    g.duration = 0.22
    g.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.5)
    return g
  }
}
