import AppKit
import CoreGraphics
import PingCore

/// League's current eight-slice wheel, drawn like lolPing's SVG (wheel.ts).
@MainActor
enum ModernWheelRenderer {
  static let innerR: CGFloat = 86, outerR: CGFloat = 188, extR: CGFloat = 288, iconR: CGFloat = 137, iconSize: CGFloat = 48
  private static let half = extR + 4

  private static func polar(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
    CGPoint(x: r * cos(deg * .pi / 180), y: r * sin(deg * .pi / 180))
  }

  /// Annular sector between radii r0 and r1, from angle a0 to a1 (degrees, clockwise from +x, y down).
  private static func sector(_ r0: CGFloat, _ r1: CGFloat, _ a0: CGFloat, _ a1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: .zero, radius: r1, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: false)
    p.addArc(center: .zero, radius: r0, startAngle: a1 * .pi / 180, endAngle: a0 * .pi / 180, clockwise: true)
    p.closeSubpath()
    return p
  }

  private static func radial(_ ctx: CGContext, clip: CGPath, center: CGPoint = .zero, radius: CGFloat,
                             stops: [(CGFloat, UInt32, CGFloat)], evenOdd: Bool = false) {
    let colors = stops.map { Drawing.color($0.1, alpha: $0.2) } as CFArray
    let locs = stops.map { $0.0 }
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locs)!
    ctx.saveGState()
    ctx.addPath(clip)
    if evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
  }

  static func render(wheel: [PingID], pixelScale: CGFloat) -> WheelArt {
    let size = CGSize(width: half * 2, height: half * 2)
    func layer(_ draw: @escaping (CGContext) -> Void) -> CGImage {
      Drawing.image(size: size, scale: pixelScale) { ctx in
        ctx.translateBy(x: half, y: half)
        draw(ctx)
      }
    }
    let mids = (0..<8).map { -90 + CGFloat($0) * 45 }

    let under = layer { ctx in
      for i in stride(from: 0, to: 8, by: 2) {
        radial(ctx, clip: sector(outerR, extR, mids[i] - 22.5, mids[i] + 22.5), radius: extR,
               stops: [(outerR / extR, 0x5C6066, 0.55), (1, 0x5C6066, 0)])
      }
      let ring = CGMutablePath()
      ring.addEllipse(in: CGRect(x: -outerR, y: -outerR, width: 2 * outerR, height: 2 * outerR))
      ring.addEllipse(in: CGRect(x: -innerR, y: -innerR, width: 2 * innerR, height: 2 * innerR))
      ctx.setAlpha(0.92)
      radial(ctx, clip: ring, radius: outerR, stops: [(innerR / outerR, 0x2A2D31, 1), (1, 0x4A4E54, 1)], evenOdd: true)
      ctx.setAlpha(1)
    }

    let highlights: [WheelImage] = (0..<8).map { i in
      WheelImage(cropping: layer { ctx in
        let reach = i % 2 == 0 ? extR : outerR
        ctx.setAlpha(0.55)
        radial(ctx, clip: sector(innerR, reach, mids[i] - 22.5, mids[i] + 22.5), radius: extR,
               stops: [(innerR / extR, 0x8A8F96, 1), (outerR / extR, 0x9AA0A8, 1), (1, 0x9AA0A8, 0)])
      }, scale: pixelScale)
    }

    let over = layer { ctx in
      ctx.setStrokeColor(Drawing.color(0xA08A5C, alpha: 0.45))
      ctx.setLineWidth(1.2)
      for m in mids {
        ctx.move(to: polar(innerR, m - 22.5))
        ctx.addLine(to: polar(outerR, m - 22.5))
      }
      ctx.strokePath()
      for (i, id) in wheel.enumerated() {
        guard let def = PingCatalog.def(id, style: .modern), case .texture(let name) = def.wheelIcon,
              let img = Textures.named(name) else { continue }
        Drawing.draw(img, centeredAt: polar(iconR, mids[i]), size: CGSize(width: iconSize, height: iconSize), ctx)
      }
      ctx.setStrokeColor(Drawing.color(0x1A1A1A, alpha: 0.6))
      ctx.setLineWidth(6)
      ctx.strokeEllipse(in: CGRect(x: -innerR - 4, y: -innerR - 4, width: 2 * innerR + 8, height: 2 * innerR + 8))
      let core = CGPath(ellipseIn: CGRect(x: -innerR, y: -innerR, width: 2 * innerR, height: 2 * innerR), transform: nil)
      radial(ctx, clip: core, center: CGPoint(x: 0, y: -10), radius: innerR, stops: [(0, 0x2C5D60, 1), (1, 0x11292C, 1)])
      ctx.setStrokeColor(Drawing.color(0xC8AA6E))
      ctx.setLineWidth(3)
      ctx.addPath(core)
      ctx.strokePath()
      ctx.setStrokeColor(Drawing.color(0x8A7448, alpha: 0.6))
      ctx.setLineWidth(1)
      ctx.strokeEllipse(in: CGRect(x: -innerR + 7, y: -innerR + 7, width: 2 * innerR - 14, height: 2 * innerR - 14))
      if let hub = Textures.named("generic_ping") {
        Drawing.draw(hub, in: CGRect(x: -20, y: -58, width: 40, height: 40), ctx)
      }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
      let label = String(localized: "wheel.cancel", defaultValue: "Cancel")
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.85, green: 0.78, blue: 0.6, alpha: 1),
      ]
      let w = (label as NSString).size(withAttributes: attrs).width
      (label as NSString).draw(at: CGPoint(x: -w / 2, y: -2), withAttributes: attrs)
      NSGraphicsContext.restoreGraphicsState()
    }

    return WheelArt(size: size, scale: pixelScale, under: under, highlights: highlights, over: over,
                    centerHot: nil, deadZone: innerR)
  }
}
