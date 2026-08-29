//
//  AudioCache.swift
//  VocalLingo
//
//  Pre-renders AVSpeechSynthesizer output to .caf files in the app's
//  Documents directory, then plays them back via AVAudioPlayer. This is
//  the "Pimsleur pattern" for dynamic TTS content: once a phrase is
//  cached, playback goes through the standard audio-file path that
//  CarPlay expects, which fixes the mid-sentence dropouts we saw with
//  live speech synthesis on CarPlay.
//
//  Cache key = SHA-1 of (text + voiceID + rate + pitch + volume)
//  Cache path = Documents/AudioCache/{lang}/{key}.caf
//

import Foundation
import AVFoundation
import CryptoKit

public struct RenderRequest {
    let text: String
    let localeCode: String
    let voiceID: String       // AVSpeechSynthesisVoice.identifier
    let rate: Float
    let pitch: Float
    let volume: Float
    /// Post-render linear gain multiplier applied to every PCM sample
    /// before we write the .caf file. 1.0 = no change; 2.0 = ~+6 dB.
    /// Used for language-specific loudness matching (e.g. Spanish voices
    /// tend to record quieter than English on Apple's TTS).
    let postGain: Float
}

/// Errors surfaced by AudioCache.
public enum AudioCacheError: Error {
    case voiceUnavailable
    case renderFailed(String)
    case writeFailed(String)
}

public final class AudioCache: @unchecked Sendable {
    public static let shared = AudioCache()

    // Serial queue so we render one phrase at a time. AVSpeechSynthesizer's
    // write(_:toBufferCallback:) is not designed for parallel use.
    private let renderQueue = DispatchQueue(label: "com.robertapolk.VocalLingo.AudioCache.render",
                                            qos: .userInitiated)

    // In-flight requests, keyed by cache file path, so two callers asking for
    // the same phrase don't render twice.
    private var inFlight: [String: [((Result<URL, Error>) -> Void)]] = [:]
    private let inFlightLock = NSLock()

    private init() {
        _ = try? Self.ensureCacheRoot()
    }

    // MARK: - Public API

    /// Returns the on-disk URL for a cached phrase, rendering it synchronously
    /// on the render queue if it doesn't exist yet. Safe to call from any
    /// thread; the completion is called on `.main`.
    public func url(for req: RenderRequest,
                    completion: @escaping (Result<URL, Error>) -> Void) {
        let path: URL
        do {
            path = try Self.cacheURL(for: req)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        if FileManager.default.fileExists(atPath: path.path) {
            DispatchQueue.main.async { completion(.success(path)) }
            return
        }

        // Deduplicate concurrent requests for the same file.
        let key = path.path
        inFlightLock.lock()
        if var waiters = inFlight[key] {
            waiters.append(completion)
            inFlight[key] = waiters
            inFlightLock.unlock()
            return
        } else {
            inFlight[key] = [completion]
        }
        inFlightLock.unlock()

        renderQueue.async { [weak self] in
            guard let self = self else { return }
            let result: Result<URL, Error>
            do {
                try self.renderToFile(req: req, dest: path)
                result = .success(path)
            } catch {
                result = .failure(error)
            }

            self.inFlightLock.lock()
            let waiters = self.inFlight[key] ?? []
            self.inFlight[key] = nil
            self.inFlightLock.unlock()

            DispatchQueue.main.async {
                for cb in waiters { cb(result) }
            }
        }
    }

    /// Fire-and-forget bulk prefetch. Each request that fails is skipped
    /// silently; overall completion is called on `.main` when the last one
    /// finishes (success OR failure).
    public func prefetch(_ requests: [RenderRequest],
                         progress: ((Int, Int) -> Void)? = nil,
                         completion: (() -> Void)? = nil) {
        let total = requests.count
        guard total > 0 else {
            DispatchQueue.main.async { completion?() }
            return
        }
        var done = 0
        let lock = NSLock()
        for req in requests {
            self.url(for: req) { _ in
                lock.lock()
                done += 1
                let now = done
                lock.unlock()
                progress?(now, total)
                if now == total {
                    completion?()
                }
            }
        }
    }

    /// Delete every cached file. Not currently wired to any UI but useful
    /// for debugging + a future Settings toggle.
    public func clear() throws {
        let root = try Self.ensureCacheRoot()
        let files = try FileManager.default.contentsOfDirectory(at: root,
                                                                includingPropertiesForKeys: nil)
        for f in files {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// On-disk size of the cache in bytes.
    public func totalBytes() -> UInt64 {
        guard let root = try? Self.ensureCacheRoot() else { return 0 }
        var total: UInt64 = 0
        if let en = FileManager.default.enumerator(at: root,
                                                   includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in en {
                let vals = try? url.resourceValues(forKeys: [.fileSizeKey])
                if let sz = vals?.fileSize { total += UInt64(sz) }
            }
        }
        return total
    }

    // MARK: - Rendering

    /// Blocking render on the current thread. Called from renderQueue.
    private func renderToFile(req: RenderRequest, dest: URL) throws {
        guard let voice = AVSpeechSynthesisVoice(identifier: req.voiceID)
                ?? AVSpeechSynthesisVoice(language: req.localeCode) else {
            throw AudioCacheError.voiceUnavailable
        }

        let utterance = AVSpeechUtterance(string: req.text)
        utterance.voice = voice
        utterance.rate = req.rate
        utterance.pitchMultiplier = req.pitch
        utterance.volume = req.volume
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0

        // AVSpeechSynthesizer.write(_:toBufferCallback:) delivers PCM buffers
        // via the callback. We stitch them into a single AVAudioFile.
        let synth = AVSpeechSynthesizer()
        var audioFile: AVAudioFile?
        var writeError: Error?

        // Temp file so we don't leave a partial .caf on disk if rendering
        // fails halfway through. Rename atomically on success.
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp.caf")

        // The callback runs on an internal queue. We use a semaphore to
        // block the render thread until we get an empty buffer (= EOF).
        let sem = DispatchSemaphore(value: 0)
        var didFinish = false

        synth.write(utterance) { (buffer: AVAudioBuffer) in
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                writeError = AudioCacheError.renderFailed("non-PCM buffer")
                if !didFinish { didFinish = true; sem.signal() }
                return
            }

            if pcm.frameLength == 0 {
                // EOF marker
                if !didFinish { didFinish = true; sem.signal() }
                return
            }

            do {
                if audioFile == nil {
                    // Use CAF because it can hold arbitrary linear PCM
                    // without a fixed header size limit — safer than WAV
                    // for potentially-long generated units.
                    audioFile = try AVAudioFile(forWriting: tmp,
                                                settings: pcm.format.settings,
                                                commonFormat: .pcmFormatFloat32,
                                                interleaved: false)
                }
                // Apply the per-language gain in place. We're running on the
                // synthesizer's internal callback thread; the buffer is ours
                // to mutate before we hand it to AVAudioFile.
                if req.postGain != 1.0,
                   let channelData = pcm.floatChannelData {
                    let frames = Int(pcm.frameLength)
                    let channels = Int(pcm.format.channelCount)
                    let gain = req.postGain
                    for ch in 0..<channels {
                        let ptr = channelData[ch]
                        for i in 0..<frames {
                            // Multiply then hard-clip to [-1, 1] to avoid
                            // wrapping if gain pushes samples over full-scale.
                            var v = ptr[i] * gain
                            if v > 1.0 { v = 1.0 } else if v < -1.0 { v = -1.0 }
                            ptr[i] = v
                        }
                    }
                }
                try audioFile?.write(from: pcm)
            } catch {
                writeError = error
                if !didFinish { didFinish = true; sem.signal() }
            }
        }

        // Cap render at 30s. Real phrases are <5s; a stuck synthesizer
        // shouldn't wedge the queue.
        let waited = sem.wait(timeout: .now() + 30)
        if waited == .timedOut {
            throw AudioCacheError.renderFailed("render timeout after 30s")
        }
        if let e = writeError { throw e }
        guard audioFile != nil else {
            throw AudioCacheError.renderFailed("no audio produced")
        }
        // Close file by dropping the reference.
        audioFile = nil

        // Atomic rename tmp → dest so partial files never appear at dest.
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    // MARK: - Paths

    private static func ensureCacheRoot() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let root = docs.appendingPathComponent("AudioCache", isDirectory: true)
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        return root
    }

    private static func cacheURL(for req: RenderRequest) throws -> URL {
        let root = try ensureCacheRoot()
        let langDir = root.appendingPathComponent(req.localeCode, isDirectory: true)
        try FileManager.default.createDirectory(at: langDir,
                                                withIntermediateDirectories: true)
        return langDir.appendingPathComponent(Self.key(for: req) + ".caf")
    }

    private static func key(for req: RenderRequest) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data(req.text.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(req.voiceID.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(String(format: "%.3f", req.rate).utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(String(format: "%.3f", req.pitch).utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(String(format: "%.3f", req.volume).utf8))
        hasher.update(data: Data("|".utf8))
        // Include postGain so raising Spanish loudness invalidates the old
        // (quiet) cached files automatically — no manual cache-clear needed.
        hasher.update(data: Data(String(format: "%.3f", req.postGain).utf8))
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
