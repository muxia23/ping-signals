import AppKit
import CoreGraphics
import PingCore

/// An image covering only part of the wheel canvas.
struct WheelImage {
  let image: CGImage
  /// Where the image sits on the canvas, in points, origin top-left, y down.
  let frame: CGRect

  /// Cuts a full-canvas image (`scale` pixels per point) down to its non-transparent pixels, copied into
  /// a bitmap of their own so the full-canvas one can be freed.
  init(cropping full: CGImage, scale: CGFloat) {
    let w = full.width, h = full.height
    var minX = w, minY = h, maxX = -1, maxY = -1
    if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
       let data = ctx.data {
      ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
      let alpha = data.bindMemory(to: UInt8.self, capacity: w * h)
      // Bitmap rows run top to bottom in memory.
      for y in 0..<h {
        let row = alpha + y * w
        for x in 0..<w where row[x] != 0 {
          minX = min(minX, x); maxX = max(maxX, x)
          minY = min(minY, y); maxY = max(maxY, y)
        }
      }
    }
    let px = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    guard maxX >= 0, let cut = full.cropping(to: px),
          let space = full.colorSpace,
          let copy = CGContext(data: nil, width: cut.width, height: cut.height, bitsPerComponent: 8, bytesPerRow: 0,
                               space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      image = full
      frame = CGRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale)
      return
    }
    copy.setBlendMode(.copy)
    copy.draw(cut, in: CGRect(x: 0, y: 0, width: cut.width, height: cut.height))
    image = copy.makeImage()!
    frame = CGRect(x: px.minX / scale, y: px.minY / scale, width: px.width / scale, height: px.height / scale)
  }
}

/// A rendered wheel: stacked images on a `size`-point canvas centred on the wheel origin. `under` and
/// `over` cover the whole canvas; highlights and the dead-zone image are cropped to their pixels.
struct WheelArt {
  let size: CGSize
  let scale: CGFloat
  let under: CGImage
  let highlights: [WheelImage]
  let over: CGImage
  /// Shown while the pointer is in the dead zone.
  let centerHot: WheelImage?
  /// In points, from the wheel centre.
  let deadZone: CGFloat

  var slots: Int { highlights.count }

  /// Composites a still frame (for previews): `hot` = highlighted slice, nil = dead zone.
  func composite(hot: Int?) -> CGImage {
    Drawing.image(size: size, scale: scale) { ctx in
      let r = CGRect(origin: .zero, size: size)
      Drawing.draw(under, in: r, ctx)
      if let h = hot { Drawing.draw(highlights[h].image, in: highlights[h].frame, ctx) }
      Drawing.draw(over, in: r, ctx)
      if hot == nil, let c = centerHot { Drawing.draw(c.image, in: c.frame, ctx) }
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
