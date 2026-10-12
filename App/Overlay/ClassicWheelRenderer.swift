import CoreGraphics
import PingCore

/// The pre-12.22 four-ping wheel, assembled from contextwheel_atlas.png sprites.
@MainActor
enum ClassicWheelRenderer {
  /// Points per atlas pixel. 1.25 → a 355 pt wheel.
  static let classicScale: CGFloat = 1.25
  private static let R: CGFloat = 142, C: CGFloat = 160, canvas: CGFloat = 320

  private static let quarter = AtlasRect(x: 1, y: 1, w: 142, h: 142)          // top-left quadrant of the frame
  private static let wedgeTop = AtlasRect(x: 169, y: 145, w: 166, h: 115)     // highlighted north wedge
  private static let wedgeSide = AtlasRect(x: 172, y: 263, w: 115, h: 166)    // highlighted west wedge
  private static let disc = AtlasRect(x: 373, y: 228, w: 135, h: 135)
  private static let shadow = AtlasRect(x: 371, y: 371, w: 140, h: 140)
  private static let center = AtlasRect(x: 0, y: 426, w: 86, h: 86)
  private static let cancel = AtlasRect(x: 96, y: 448, w: 60, h: 60)
  private static let cancelHot = AtlasRect(x: 166, y: 448, w: 60, h: 60)

  static func render(wheel: [PingID], pixelScale: CGFloat) -> WheelArt {
    let s = classicScale
    let size = CGSize(width: canvas * s, height: canvas * s)
    let px = s * pixelScale
    let atlasSize = CGSize(width: canvas, height: canvas)
    func sprite(_ r: AtlasRect) -> CGImage { Textures.atlas(r)! }
    func natural(_ r: AtlasRect) -> CGSize { CGSize(width: r.w, height: r.h) }
    // Every layer is drawn in atlas pixels and scaled by `s` via the bitmap scale.
    func layer(_ draw: @escaping (CGContext) -> Void) -> CGImage {
      Drawing.image(size: atlasSize, scale: px, draw)
    }

    let under = layer { ctx in
      Drawing.draw(sprite(shadow), centeredAt: CGPoint(x: C, y: C + 3), size: CGSize(width: 2 * R + 8, height: 2 * R + 8), ctx)
      let discRect = CGRect(x: C - R, y: C - R, width: 2 * R, height: 2 * R)
      // Darken the grey disc like the game's dark base: scale its RGB by 0.28, keep its (half) alpha.
      ctx.beginTransparencyLayer(auxiliaryInfo: nil)
      Drawing.draw(sprite(disc), in: discRect, ctx)
      ctx.setBlendMode(.sourceAtop)
      ctx.setFillColor(CGColor(gray: 0, alpha: 0.72))
      ctx.fill(discRect)
      ctx.endTransparencyLayer()
    }

    // North and west wedges; south and east are the same sprites turned 180° about the wheel centre.
    let highlights: [CGImage] = (0..<4).map { i in
      layer { ctx in
        ctx.translateBy(x: C, y: C)
        ctx.rotate(by: i >= 2 ? .pi : 0)
        ctx.translateBy(x: -C, y: -C)
        if i % 2 == 0 {
          let sz = natural(wedgeTop)
          Drawing.draw(sprite(wedgeTop), centeredAt: CGPoint(x: C, y: C - R + sz.height / 2 + 4), size: sz, ctx)
        } else {
          let sz = natural(wedgeSide)
          Drawing.draw(sprite(wedgeSide), centeredAt: CGPoint(x: C - R + sz.width / 2 + 4, y: C), size: sz, ctx)
        }
      }
    }
    // Slice order is N, E, S, W: highlights above were built as N, W, S, E — reorder.
    let ordered = [highlights[0], highlights[3], highlights[2], highlights[1]]

    let over = layer { ctx in
      for k in 0..<4 {
        ctx.saveGState()
        ctx.translateBy(x: C, y: C)
        ctx.rotate(by: CGFloat(k) * .pi / 2)                  // clockwise in y-down space
        ctx.translateBy(x: -C, y: -C)
        Drawing.draw(sprite(quarter), in: CGRect(x: C - R, y: C - R, width: R, height: R), ctx)
        ctx.restoreGState()
      }
      Drawing.draw(sprite(center), centeredAt: CGPoint(x: C, y: C), size: natural(center), ctx)
      Drawing.draw(sprite(cancel), centeredAt: CGPoint(x: C, y: C), size: natural(cancel), ctx)
      let dirs: [CGPoint] = [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)]
      for (i, id) in wheel.enumerated() {
        guard let def = PingCatalog.def(id, style: .classic), case .atlas(let r) = def.wheelIcon else { continue }
        let p = CGPoint(x: C + dirs[i].x * R * 0.62, y: C + dirs[i].y * R * 0.62)
        Drawing.draw(sprite(r), centeredAt: p, size: natural(r), ctx)
      }
    }

    let hot = layer { ctx in
      Drawing.draw(sprite(cancelHot), centeredAt: CGPoint(x: C, y: C), size: natural(cancelHot), ctx)
    }

    return WheelArt(size: size, scale: pixelScale, under: under, highlights: ordered, over: over,
                    centerHot: hot, deadZone: CGFloat(center.w) / 2 * s)
  }
}
