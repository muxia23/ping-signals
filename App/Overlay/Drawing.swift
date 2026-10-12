import AppKit
import CoreGraphics
import PingCore

/// Bitmap drawing in a y-down coordinate space (like SVG / the atlas), at a given pixel scale.
enum Drawing {
  /// Draws into a bitmap of `size` points × `scale`, origin at the top-left, y down.
  static func image(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
    let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
  }

  /// Draws `img` into `rect` of a y-down context without flipping it.
  static func draw(_ img: CGImage, in rect: CGRect, _ ctx: CGContext, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
  }

  /// Draws `img` centred at `center` with its natural size × `scale`, rotated clockwise by `degrees`.
  static func draw(_ img: CGImage, centeredAt center: CGPoint, size: CGSize, degrees: CGFloat = 0, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    draw(img, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), ctx)
    ctx.restoreGState()
  }

  static func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
  }
}

/// Bundled textures, loaded once.
@MainActor
enum Textures {
  private static var cache: [String: CGImage] = [:]

  static func named(_ name: String) -> CGImage? {
    if let c = cache[name] { return c }
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    cache[name] = img
    return img
  }

  /// A sprite cut from the classic wheel atlas.
  static func atlas(_ r: AtlasRect) -> CGImage? {
    named("contextwheel_atlas")?.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h))
  }

  /// A white/grey texture recoloured with `rgb`, keeping its alpha and brightness.
  static func tinted(_ name: String, _ rgb: UInt32) -> CGImage? {
    let key = "\(name)#\(rgb)"
    if let c = cache[key] { return c }
    guard let src = named(name) else { return nil }
    let size = CGSize(width: src.width, height: src.height)
    let out = Drawing.image(size: size, scale: 1) { ctx in
      let rect = CGRect(origin: .zero, size: size)
      Drawing.draw(src, in: rect, ctx)
      ctx.setBlendMode(.multiply)
      ctx.setFillColor(Drawing.color(rgb))
      ctx.fill(rect)
      ctx.setBlendMode(.destinationIn)
      Drawing.draw(src, in: rect, ctx)
    }
    cache[key] = out
    return out
  }
}
