import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Playback engine for VocalLingo.
///
/// v5 change: instead of driving AVSpeechSynthesizer live on every phrase
/// (which caused mid-sentence dropouts on CarPlay because CarPlay releases
/// the audio route whenever the synthesizer's on-the-fly buffer production
/// stalls), we pre-render each phrase to a .caf file via AudioCache and
/// play the file with AVAudioPlayer. Same code path as Apple Music / any
/// audiobook app, which is why CarPlay holds the route open reliably.
///
/// The public API (speak/stop/updateNowPlaying + onRemoteNext/Prev) is
/// unchanged so PracticeView, UnitTestView, and CarPlaySceneDelegate work
/// without modification. The first time a phrase is spoken it blocks for
/// ~200ms while it renders; every subsequent play is instant. Use
/// prefetch(phrases:) to warm the cache when a unit view appears.
public final class VoiceManager: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, ObservableObject {
    public static let shared = VoiceManager()

    // Kept only so AVSpeechSynthesizerDelegate protocol conformance still
    // compiles for anything downstream that references it. Not used for
    // playback anymore.
    private let synthesizer = AVSpeechSynthesizer()

    // Real playback goes through here.
    private var player: AVAudioPlayer?

    @Published public var isSpeaking: Bool = false
    @Published public var activePhraseID: UUID? = nil

    private var completionHandler: (() -> Void)?
    private var currentUnitTitle: String = "VocalLingo"
    private var currentPhraseText: String = ""
    private var didSetAudioCategory: Bool = false
    private var didWireRemoteCommands: Bool = false

    // Playback tuning. Kept centralised so the cache key stays consistent
    // with what we render.
    private let playbackRate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.95
    private let playbackPitch: Float = 1.0
    private let playbackVolume: Float = 1.0

    /// Per-language render-time gain. Apple's Spanish voices (Monica,
    /// Paulina, Jorge) tend to record several dB quieter than the US
    /// English voices (Samantha, Alex), which is very audible on CarPlay.
    /// We compensate at render time so cached .caf files ship loud.
    /// 1.0 = no change, 2.0 ≈ +6 dB. Hard-clipped in AudioCache to avoid
    /// wrap-around distortion.
    private static func postGain(for localeCode: String) -> Float {
        let lc = localeCode.lowercased()
        if lc.hasPrefix("es") { return 2.0 }   // Spanish: +6 dB
        if lc.hasPrefix("fr") { return 1.6 }   // French: gentler boost
        if lc.hasPrefix("ja") { return 1.6 }   // Japanese: gentler boost
        return 1.0                              // English and unknowns: unchanged
    }

    // Called by CarPlay/remote to advance/previous.
    public var onRemoteNext: (() -> Void)?
    public var onRemotePrevious: (() -> Void)?

    private override init() {
        super.init()
        self.synthesizer.delegate = self
        wireRemoteCommandCenter()
        observeInterruptions()
        observeAppLifecycle()
    }

    // MARK: - Audio session

    /// One-shot category setup. On iOS 26 AVAudioSession sometimes rejects
    /// setCategory with -50 depending on which subsystem currently owns
    /// the shared session; we log and move on because .playback is the
    /// default the system picks for AVAudioPlayer output anyway.
    private func configureAudioSessionIfNeeded() {
        guard !didSetAudioCategory else { return }
        didSetAudioCategory = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .spokenAudio,
                                    options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: [])
            print("[VoiceManager] Audio session ready: \(session.category.rawValue), \(session.mode.rawValue)")
        } catch {
            print("[VoiceManager] setCategory/setActive skipped: \(error)")
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeVal)
            else { return }
            if type == .began {
                self?.player?.pause()
                self?.isSpeaking = false
                self?.republishNowPlayingRate()
            } else if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                self?.player?.play()
                self?.isSpeaking = (self?.player?.isPlaying == true)
                self?.republishNowPlayingRate()
            }
        }
    }

    /// Hand the audio route back cleanly when we background or terminate.
    private func observeAppLifecycle() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.deactivateIfIdle()
        }
        nc.addObserver(forName: UIApplication.willTerminateNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.deactivateIfIdle(force: true)
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.republishNowPlayingRate()
        }
    }

    private func deactivateIfIdle(force: Bool = false) {
        if !force && (player?.isPlaying == true) { return }
        player?.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false,
                                                          options: .notifyOthersOnDeactivation)
            didSetAudioCategory = false  // re-arm on next speak()
            print("[VoiceManager] Audio session deactivated (force=\(force))")
        } catch {
            print("[VoiceManager] Deactivate skipped: \(error)")
        }
    }

    // MARK: - Remote command center

    private func wireRemoteCommandCenter() {
        guard !didWireRemoteCommands else { return }
        didWireRemoteCommands = true

        UIApplication.shared.beginReceivingRemoteControlEvents()

        let rcc = MPRemoteCommandCenter.shared()
        rcc.playCommand.isEnabled = true
        rcc.pauseCommand.isEnabled = true
        rcc.nextTrackCommand.isEnabled = true
        rcc.previousTrackCommand.isEnabled = true

        rcc.playCommand.addTarget { [weak self] _ in
            guard let self = self, let p = self.player else { return .commandFailed }
            if !p.isPlaying {
                p.play()
                self.isSpeaking = true
                self.republishNowPlayingRate()
            }
            return .success
        }
        rcc.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isSpeaking = false
            self?.republishNowPlayingRate()
            return .success
        }
        rcc.nextTrackCommand.addTarget { [weak self] _ in
            self?.onRemoteNext?()
            return .success
        }
        rcc.previousTrackCommand.addTarget { [weak self] _ in
            self?.onRemotePrevious?()
            return .success
        }
    }

    // MARK: - Now Playing

    public func updateNowPlaying(unitTitle: String, phrase: String) {
        currentUnitTitle = unitTitle
        currentPhraseText = phrase
        publishNowPlaying()
    }

    private func publishNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentPhraseText.isEmpty ? "VocalLingo" : currentPhraseText
        info[MPMediaItemPropertyArtist] = currentUnitTitle
        info[MPMediaItemPropertyAlbumTitle] = "VocalLingo"
        // If we know the real duration (from the player), use it; else a
        // conservative default so the lock screen renders a progress bar.
        info[MPMediaItemPropertyPlaybackDuration] = player?.duration ?? 60.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        print("[VoiceManager] NowPlaying → title=\(currentPhraseText.prefix(40)) rate=\(isSpeaking ? 1.0 : 0.0)")
    }

    private func republishNowPlayingRate() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Public API

    /// Speak a phrase in the given locale. Renders to a cached .caf file on
    /// first use (blocks ~200ms), plays back via AVAudioPlayer thereafter.
    public func speak(text: String,
                      localeCode: String,
                      phraseID: UUID? = nil,
                      completion: (() -> Void)? = nil) {
        // Stop any current playback so a fresh speak() overrides it.
        player?.stop()
        player = nil

        configureAudioSessionIfNeeded()

        self.completionHandler = completion
        self.activePhraseID = phraseID

        guard let voice = Self.bestVoice(for: localeCode) else {
            print("[VoiceManager] No voice available for \(localeCode); dropping utterance")
            completion?()
            return
        }
        print("[VoiceManager] Voice picked: \(voice.identifier) " +
              "quality=\(voice.quality.rawValue) for \(localeCode)")

        let req = RenderRequest(text: text,
                                localeCode: localeCode,
                                voiceID: voice.identifier,
                                rate: playbackRate,
                                pitch: playbackPitch,
                                volume: playbackVolume,
                                postGain: Self.postGain(for: localeCode))

        // Publish Now Playing immediately so the lock screen updates even
        // if the render takes a beat on first hit.
        currentPhraseText = text
        publishNowPlaying()

        AudioCache.shared.url(for: req) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let e):
                print("[VoiceManager] Cache render failed: \(e); calling completion")
                self.isSpeaking = false
                self.publishNowPlaying()
                self.completionHandler?()
            case .success(let url):
                self.startPlayback(fileURL: url)
            }
        }
    }

    private func startPlayback(fileURL: URL) {
        do {
            let p = try AVAudioPlayer(contentsOf: fileURL)
            p.delegate = self
            p.volume = playbackVolume
            p.prepareToPlay()
            self.player = p
            self.isSpeaking = true
            self.publishNowPlaying()
            let ok = p.play()
            if !ok {
                print("[VoiceManager] AVAudioPlayer.play() returned false")
                self.isSpeaking = false
                self.publishNowPlaying()
                self.completionHandler?()
            }
        } catch {
            print("[VoiceManager] AVAudioPlayer init failed: \(error)")
            self.isSpeaking = false
            self.publishNowPlaying()
            self.completionHandler?()
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        isSpeaking = false
        activePhraseID = nil
        republishNowPlayingRate()
    }

    // MARK: - Prefetch

    /// Warm the cache for a list of (text, localeCode) pairs — usually the
    /// full set of English + translated + repeat phrases for the current
    /// unit. Progress and completion fire on `.main`.
    public func prefetch(_ pairs: [(text: String, localeCode: String)],
                         progress: ((Int, Int) -> Void)? = nil,
                         completion: (() -> Void)? = nil) {
        let requests: [RenderRequest] = pairs.compactMap { pair in
            guard let voice = Self.bestVoice(for: pair.localeCode) else { return nil }
            return RenderRequest(text: pair.text,
                                 localeCode: pair.localeCode,
                                 voiceID: voice.identifier,
                                 rate: playbackRate,
                                 pitch: playbackPitch,
                                 volume: playbackVolume,
                                 postGain: Self.postGain(for: pair.localeCode))
        }
        AudioCache.shared.prefetch(requests, progress: progress, completion: completion)
    }

    // MARK: - Voice selection

    /// Best available voice for a locale, with graceful fallback.
    static func bestVoice(for localeCode: String) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let exact = allVoices.filter { $0.language == localeCode }
        if let v = exact.first(where: { $0.quality == .premium })
            ?? exact.first(where: { $0.quality == .enhanced })
            ?? exact.first {
            return v
        }

        let langPrefix = String(localeCode.prefix(2))
        let family = allVoices.filter { $0.language.hasPrefix(langPrefix) }
        if let v = family.first(where: { $0.quality == .premium })
            ?? family.first(where: { $0.quality == .enhanced })
            ?? family.first {
            return v
        }

        return AVSpeechSynthesisVoice(language: localeCode)
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.activePhraseID = nil
            self.publishNowPlaying()
            let cb = self.completionHandler
            self.completionHandler = nil
            cb?()
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        print("[VoiceManager] AVAudioPlayer decode error: \(String(describing: error))")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.publishNowPlaying()
            self.completionHandler?()
            self.completionHandler = nil
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate (vestigial; live synthesis no longer used)

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {}
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
