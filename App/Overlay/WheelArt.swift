import AppKit
import CoreGraphics
import PingCore

/// A rendered wheel: stacked images, all `size` points, centred on the wheel origin.
struct WheelArt {
  let size: CGSize
  let scale: CGFloat
  let under: CGImage
  let highlights: [CGImage]
  let over: CGImage
  /// Shown while the pointer is in the dead zone.
  let centerHot: CGImage?
  /// In points, from the wheel centre.
  let deadZone: CGFloat

  var slots: Int { highlights.count }

  /// Composites a still frame (for previews): `hot` = highlighted slice, nil = dead zone.
  func composite(hot: Int?) -> CGImage {
    Drawing.image(size: size, scale: scale) { ctx in
      let r = CGRect(origin: .zero, size: size)
      Drawing.draw(under, in: r, ctx)
      if let h = hot { Drawing.draw(highlights[h], in: r, ctx) }
      Drawing.draw(over, in: r, ctx)
      if hot == nil, let c = centerHot { Drawing.draw(c, in: r, ctx) }
    }
  }

  /// Writes the idle frame and one frame per highlighted slice, side by side, as a PNG.
  func writePreview(to url: URL) throws {
    let frames = [composite(hot: nil)] + (0..<slots).map { composite(hot: $0) }
    let sheet = Drawing.image(size: CGSize(width: size.width * CGFloat(frames.count), height: size.height), scale: scale) { ctx in
      ctx.setFillColor(Drawing.color(0x3A4A42))
      ctx.fill(CGRect(x: 0, y: 0, width: size.width * CGFloat(frames.count), height: size.height))
      for (i, f) in frames.enumerated() {
        Drawing.draw(f, in: CGRect(x: size.width * CGFloat(i), y: 0, width: size.width, height: size.height), ctx)
      }
    }
    let rep = NSBitmapImageRep(cgImage: sheet)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
  }
}
