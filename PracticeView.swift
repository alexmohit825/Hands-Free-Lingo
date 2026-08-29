import SwiftUI

public struct PracticeView: View {
    let unit: Unit
    let selectedLanguage: Language
    @Binding var isAutoplayActive: Bool
    let onUnitPassed: () -> Void
    let onNextUnit: () -> Void
    /// v8: parent supplies a lookup for the next unit so we can prefetch
    /// its audio in the background before autoplay crosses the unit
    /// boundary. Return nil if there is no next unit (end of curriculum).
    /// Defaults to `nil` so existing call sites that don't need warming
    /// keep compiling.
    var nextUnitLookup: (() -> Unit?)? = nil

    @StateObject private var voiceManager = VoiceManager.shared
    @State private var repeatingPhraseID: UUID? = nil
    @State private var repeatStage: String = "ready" // ready, english, target, repeating
    @State private var repeatCountdown: Int = 3
    @State private var isTestActive: Bool = false
    @State private var autoplayPhraseIndex: Int = 0
    // v6: prefetch state. Autoplay is gated on prefetch completion so
    // CarPlay plays back cache hits (no mid-phrase render latency).
    @State private var prefetchDone: Bool = false
    @State private var prefetchProgress: (done: Int, total: Int) = (0, 0)
    @State private var pendingAutoplayStart: Bool = false
    /// v8: guard so we only kick off next-unit prefetch once per unit view.
    @State private var didWarmNextUnit: Bool = false

    // Timing constants (seconds)
    private let englishToTargetGap: Double = 0.15  // brief pause between EN and target
    private let targetToRepeatGap: Double = 0.20   // brief pause before repeat window opens
    private let repeatWindow: Double = 3.0         // user's repeat window
    private let phraseToPhraseGap: Double = 0.35   // brief pause before next phrase

    public var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.05, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 16) {
                header
                autoplayCard
                testCard
                phraseList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isTestActive) {
            UnitTestView(unit: unit, selectedLanguage: selectedLanguage, onPass: {
                onUnitPassed()
            })
        }
        .onAppear {
            // Kick off the audio-cache prefetch as soon as the unit view
            // appears — rendering all English + target phrases up-front
            // means autoplay plays back cached .caf files (bulletproof on
            // CarPlay) instead of racing the synthesizer per phrase.
            startPrefetchIfNeeded()
            if isAutoplayActive {
                autoplayPhraseIndex = 0
                pendingAutoplayStart = true
                startAutoplayIfReady()
            }
        }
        .onChange(of: prefetchDone) { _, done in
            if done && pendingAutoplayStart {
                pendingAutoplayStart = false
                startAutoplayLoop()
            }
        }
        .onDisappear { stopAutoplay() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(unit.title)
                .font(.system(.title3, design: .rounded)).fontWeight(.black)
                .foregroundColor(.white)
            Text(unit.description)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20).padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var autoplayCard: some View {
        HStack(spacing: 12) {
            Circle().fill(isAutoplayActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(isAutoplayActive ? "HANDS-FREE AUTOPLAY ACTIVE" : "HANDS-FREE AUTOPLAY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(isAutoplayActive
                     ? "Phrase \(autoplayPhraseIndex + 1)/\(unit.phrases.count) · EN → \(selectedLanguage.rawValue) → repeat"
                     : "English, then target language, then 3s for you to repeat.")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: {
                if isAutoplayActive { stopAutoplay() }
                else {
                    isAutoplayActive = true
                    autoplayPhraseIndex = 0
                    pendingAutoplayStart = true
                    startPrefetchIfNeeded()
                    startAutoplayIfReady()
                }
            }) {
                Text(isAutoplayActive
                     ? "STOP"
                     : (!prefetchDone && prefetchProgress.total > 0
                        ? "PREP \(prefetchProgress.done)/\(prefetchProgress.total)"
                        : "START"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(isAutoplayActive ? Color.red : Color.green)
                    .cornerRadius(10)
            }
        }
        .padding(12)
        .background(Color.white.opacity(isAutoplayActive ? 0.06 : 0.02))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(isAutoplayActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private var testCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to verify?")
                    .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Pass with 80% or more to unlock certification.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: { isTestActive = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Take Test")
                }
                .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.blue).foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding(14).background(Color.blue.opacity(0.08))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private var phraseList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(unit.phrases) { phrase in
                    phraseRow(phrase)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    private func phraseRow(_ phrase: Phrase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    Text(phrase.english)
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phrase.translation)
                        .font(.system(.headline, design: .rounded)).fontWeight(.bold)
                        .foregroundColor(.blue)
                    if let rom = phrase.romanization {
                        Text(rom)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    if let exEng = phrase.exampleEnglish, let exTr = phrase.exampleTranslation {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\"\(exEng)\"")
                                .font(.system(size: 10)).italic().foregroundColor(.gray)
                            Text("\"\(exTr)\"")
                                .font(.system(size: 10)).fontWeight(.semibold)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: {
                        // Preview: EN then target (no repeat window)
                        voiceManager.updateNowPlaying(unitTitle: unit.title, phrase: phrase.english)
                        voiceManager.speak(text: phrase.english, localeCode: "en-US", phraseID: phrase.id) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + englishToTargetGap) {
                                voiceManager.updateNowPlaying(unitTitle: unit.title, phrase: phrase.translation)
                                voiceManager.speak(text: phrase.translation,
                                                   localeCode: selectedLanguage.localeCode,
                                                   phraseID: phrase.id)
                            }
                        }
                    }) {
                        Image(systemName: voiceManager.activePhraseID == phrase.id ? "speaker.wave.3.fill" : "play.fill")
                            .font(.system(size: 12)).foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(voiceManager.activePhraseID == phrase.id ? Color.blue : Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    Button(action: { startSinglePhraseRepeat(phrase: phrase) }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12)).foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(repeatingPhraseID == phrase.id ? Color.green : Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(12).background(Color.white.opacity(0.03)).cornerRadius(16)

            if repeatingPhraseID == phrase.id {
                repeatStatusBar
            }
        }
        .padding(14).background(Color.white.opacity(0.02)).cornerRadius(18)
    }

    private var repeatStatusBar: some View {
        VStack(spacing: 6) {
            if repeatStage == "english" {
                statusRow(color: .gray, text: "Speaking English…")
            } else if repeatStage == "target" {
                statusRow(color: .blue, text: "Speaking \(selectedLanguage.rawValue)…")
            } else if repeatStage == "repeating" {
                statusRow(color: .green, text: "Your turn — repeat now (\(repeatCountdown)s)")
            }
        }
        .padding(10).frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.02)).cornerRadius(12)
    }

    private func statusRow(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - Autoplay loop (EN → target → 3s repeat → next)

    // MARK: - v6 prefetch (Pimsleur-pattern warmup)

    private func startPrefetchIfNeeded() {
        guard !prefetchDone && prefetchProgress.total == 0 else { return }
        // For each phrase we render both the English audio AND the target-
        // language audio, so autoplay's EN→target→repeat loop hits pure
        // cache. Skips empty strings defensively.
        var pairs: [(text: String, localeCode: String)] = []
        for p in unit.phrases {
            if !p.english.isEmpty {
                pairs.append((p.english, "en-US"))
            }
            if !p.translation.isEmpty {
                pairs.append((p.translation, selectedLanguage.localeCode))
            }
        }
        prefetchProgress = (0, pairs.count)
        voiceManager.prefetch(pairs, progress: { done, total in
            prefetchProgress = (done, total)
        }, completion: {
            prefetchDone = true
        })
    }

    private func startAutoplayIfReady() {
        if prefetchDone {
            pendingAutoplayStart = false
            startAutoplayLoop()
        }
        // else: onChange(of: prefetchDone) will start it when prefetch completes.
    }

    private func stopAutoplay() {
        isAutoplayActive = false
        voiceManager.stop()
        repeatingPhraseID = nil
        repeatStage = "ready"
    }

    private func startAutoplayLoop() {
        guard isAutoplayActive else { return }
        guard autoplayPhraseIndex < unit.phrases.count else {
            onNextUnit()
            return
        }
        // v8: once we cross 60% of this unit, quietly start rendering the
        // next unit's audio in the background so the transition between
        // units is instant instead of triggering a fresh PREP wait.
        warmNextUnitIfNeeded()
        let phrase = unit.phrases[autoplayPhraseIndex]
        speakEnglishThenTargetThenRepeat(phrase: phrase, isAutoplay: true)
    }

    /// v8: prefetch the next unit's phrases (English + target) into
    /// AudioCache while the current unit is still playing. Runs at most
    /// once per PracticeView appearance and only when autoplay has
    /// progressed past 60% of the current unit.
    private func warmNextUnitIfNeeded() {
        guard !didWarmNextUnit else { return }
        guard unit.phrases.count > 0 else { return }
        let progress = Double(autoplayPhraseIndex) / Double(unit.phrases.count)
        guard progress >= 0.6 else { return }
        guard let lookup = nextUnitLookup, let next = lookup() else { return }

        didWarmNextUnit = true
        var pairs: [(text: String, localeCode: String)] = []
        for p in next.phrases {
            if !p.english.isEmpty { pairs.append((p.english, "en-US")) }
            if !p.translation.isEmpty {
                pairs.append((p.translation, selectedLanguage.localeCode))
            }
        }
        guard !pairs.isEmpty else { return }
        // Fire and forget — no UI progress. The VoiceManager prefetch runs
        // on a background queue; any phrase already cached is a no-op, so
        // this is cheap once the user has been through the unit before.
        voiceManager.prefetch(pairs, progress: nil, completion: nil)
    }

    private func startSinglePhraseRepeat(phrase: Phrase) {
        speakEnglishThenTargetThenRepeat(phrase: phrase, isAutoplay: false)
    }

    private func speakEnglishThenTargetThenRepeat(phrase: Phrase, isAutoplay: Bool) {
        repeatingPhraseID = phrase.id
        repeatStage = "english"

        // 1. Speak English
        voiceManager.updateNowPlaying(unitTitle: unit.title, phrase: phrase.english)
        voiceManager.speak(text: phrase.english, localeCode: "en-US", phraseID: phrase.id) {
            guard shouldContinue(isAutoplay: isAutoplay) else { return }
            // 2. Brief pause, then speak target language
            DispatchQueue.main.asyncAfter(deadline: .now() + englishToTargetGap) {
                guard shouldContinue(isAutoplay: isAutoplay) else { return }
                repeatStage = "target"
                voiceManager.updateNowPlaying(unitTitle: unit.title, phrase: phrase.translation)
                voiceManager.speak(text: phrase.translation,
                                   localeCode: selectedLanguage.localeCode,
                                   phraseID: phrase.id) {
                    guard shouldContinue(isAutoplay: isAutoplay) else { return }
                    // 3. Open the 3-second repeat window
                    DispatchQueue.main.asyncAfter(deadline: .now() + targetToRepeatGap) {
                        guard shouldContinue(isAutoplay: isAutoplay) else { return }
                        beginRepeatWindow(phrase: phrase, isAutoplay: isAutoplay)
                    }
                }
            }
        }
    }

    private func beginRepeatWindow(phrase: Phrase, isAutoplay: Bool) {
        repeatStage = "repeating"
        repeatCountdown = Int(repeatWindow)
        voiceManager.updateNowPlaying(unitTitle: unit.title,
                                      phrase: "Repeat: \(phrase.translation)")

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard shouldContinue(isAutoplay: isAutoplay) else {
                timer.invalidate()
                return
            }
            if repeatCountdown > 1 {
                repeatCountdown -= 1
            } else {
                timer.invalidate()
                // 4. Done with this phrase — advance
                DispatchQueue.main.asyncAfter(deadline: .now() + phraseToPhraseGap) {
                    if isAutoplay && isAutoplayActive {
                        repeatingPhraseID = nil
                        repeatStage = "ready"
                        autoplayPhraseIndex += 1
                        startAutoplayLoop()
                    } else {
                        repeatingPhraseID = nil
                        repeatStage = "ready"
                    }
                }
            }
        }
    }

    private func shouldContinue(isAutoplay: Bool) -> Bool {
        // Autoplay flow requires the top-level switch; single-phrase flow just needs
        // the row to still be the active one.
        if isAutoplay { return isAutoplayActive }
        return repeatingPhraseID != nil
    }
}
// FILE COMPLETE
