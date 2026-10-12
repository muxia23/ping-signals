import AVFoundation
import PingCore

/// Plays pre-decoded sounds with low latency. At most 8 overlap; more are skipped (the ping still shows).
/// The engine starts on the first sound and stops after a few idle seconds, so an idle app costs no CPU.
///
/// All AVAudioEngine work runs on a private serial queue: callers (the event tap on the main run loop)
/// only enqueue, so a slow `engine.start()` never holds up system mouse input.
/// `@unchecked Sendable`: after `init` returns, every mutable property is read and written only on `queue`.
final class SoundPlayer: @unchecked Sendable {
  private static let voices = 8
  private static let idleStop: TimeInterval = 5

  private let queue = DispatchQueue(label: "com.muxia.ping-signals.audio", qos: .userInteractive)
  private let engine = AVAudioEngine()
  private var buffers: [String: AVAudioPCMBuffer] = [:]
  private var players: [AVAudioPlayerNode] = []
  private var busy = Set<Int>()
  /// Bumped each time a voice is (re)used, so a late completion from an earlier sound can't free it.
  private var voiceGeneration = [Int](repeating: 0, count: SoundPlayer.voices)
  /// Bumped whenever an idle stop is scheduled or cancelled; a pending stop runs only if it still matches.
  private var idleGeneration = 0
  private var configObserver: NSObjectProtocol?

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
      // Every voice is connected with one format, so every buffer must share it.
      if let format, file.processingFormat != format {
        NSLog("ping-signals: sound \(name) skipped: format \(file.processingFormat) differs from \(format)")
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
    // Output device or sample rate changed: the system has stopped the engine, and stopped players
    // may never report their buffers as played back. Free every voice.
    configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                            object: engine, queue: nil) { [weak self] _ in
      guard let self else { return }
      self.queue.async { self.resetVoices() }
    }
  }

  deinit {
    if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
  }

  /// Starts the engine ahead of a likely sound (a wheel just opened) without playing anything.
  func warmUp() {
    queue.async { [self] in
      guard startEngine() else { return }
      if busy.isEmpty { scheduleIdleStop() }
    }
  }

  /// Callable from any thread; returns immediately.
  func play(_ name: String, volume: Float) {
    guard volume > 0 else { return }
    queue.async { [self] in playOnQueue(name, volume: volume) }
  }

  // MARK: Queue-confined

  private func startEngine() -> Bool {
    if engine.isRunning { return true }
    do { try engine.start(); return true } catch {
      NSLog("ping-signals: audio engine failed: \(error)")
      return false
    }
  }

  private func playOnQueue(_ name: String, volume: Float) {
    guard let buf = buffers[name],
          let i = players.indices.first(where: { !busy.contains($0) }),
          startEngine() else { return }
    idleGeneration += 1           // cancels a pending idle stop
    busy.insert(i)
    voiceGeneration[i] += 1
    let g = voiceGeneration[i]
    let p = players[i]
    p.volume = volume
    p.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
      guard let self else { return }
      self.queue.async { self.finished(i, generation: g) }
    }
    p.play()
  }

  private func finished(_ i: Int, generation g: Int) {
    guard voiceGeneration[i] == g, busy.contains(i) else { return }
    players[i].stop()
    busy.remove(i)
    if busy.isEmpty { scheduleIdleStop() }
  }

  private func resetVoices() {
    for (i, p) in players.enumerated() {
      p.stop()
      voiceGeneration[i] += 1
    }
    busy.removeAll()
    scheduleIdleStop()
  }

  private func scheduleIdleStop() {
    idleGeneration += 1
    let g = idleGeneration
    queue.asyncAfter(deadline: .now() + Self.idleStop) { [weak self] in
      guard let self, self.idleGeneration == g, self.busy.isEmpty else { return }
      self.engine.stop()
    }
  }
}
