import AVFoundation
import PingCore

/// Plays pre-decoded sounds with low latency. At most 8 overlap; more are skipped (the ping still shows).
/// The engine starts on the first sound and stops after a few idle seconds, so an idle app costs no CPU.
@MainActor
final class SoundPlayer {
  private static let voices = 8
  private static let idleStop: TimeInterval = 5

  private let engine = AVAudioEngine()
  private var buffers: [String: AVAudioPCMBuffer] = [:]
  private var players: [AVAudioPlayerNode] = []
  private var busy = Set<Int>()
  private var stopTimer: Timer?

  init(names: [String]) {
    var format: AVAudioFormat?
    for name in names {
      guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
            let file = try? AVAudioFile(forReading: url),
            let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buf)) != nil else {
        NSLog("ping-signals: sound \(name) failed to load")
        continue
      }
      buffers[name] = buf
      format = format ?? file.processingFormat
    }
    for _ in 0..<Self.voices {
      let p = AVAudioPlayerNode()
      engine.attach(p)
      engine.connect(p, to: engine.mainMixerNode, format: format)
      players.append(p)
    }
  }

  func play(_ name: String, volume: Float) {
    guard volume > 0, let buf = buffers[name],
          let i = players.indices.first(where: { !busy.contains($0) }) else { return }
    if !engine.isRunning {
      do { try engine.start() } catch { NSLog("ping-signals: audio engine failed: \(error)"); return }
    }
    stopTimer?.invalidate()
    stopTimer = nil
    busy.insert(i)
    let p = players[i]
    p.volume = volume
    p.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor in self?.finished(i) }
    }
    p.play()
  }

  private func finished(_ i: Int) {
    players[i].stop()
    busy.remove(i)
    guard busy.isEmpty else { return }
    stopTimer = Timer.scheduledTimer(withTimeInterval: Self.idleStop, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.busy.isEmpty else { return }
        self.engine.stop()
      }
    }
  }
}
