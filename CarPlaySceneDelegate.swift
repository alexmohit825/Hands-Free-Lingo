import CarPlay
import UIKit

public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    // Active playback state
    private var activeUnit: Unit?
    private var activePhraseIndex: Int = 0
    private var activeLanguage: Language = .spanish
    private var repeatTimer: Timer?

    // Timing constants (matches phone-side PracticeView)
    private let englishToTargetGap: Double = 0.15
    private let targetToRepeatGap: Double = 0.20
    private let repeatWindow: Double = 3.0
    private let phraseToPhraseGap: Double = 0.35

    // MARK: - CPTemplateApplicationSceneDelegate

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didConnect interfaceController")
        self.interfaceController = interfaceController

        let tabTemplate = CPTabBarTemplate(templates: [
            listTemplate(for: .spanish),
            listTemplate(for: .french),
            listTemplate(for: .german),
            listTemplate(for: .japanese)
        ])

        interfaceController.setRootTemplate(tabTemplate, animated: false, completion: nil)

        // Wire the car's next/previous transport buttons to advance phrases.
        VoiceManager.shared.onRemoteNext = { [weak self] in
            self?.advancePhrase(by: 1)
        }
        VoiceManager.shared.onRemotePrevious = { [weak self] in
            self?.advancePhrase(by: -1)
        }
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didDisconnect")
        self.interfaceController = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        VoiceManager.shared.onRemoteNext = nil
        VoiceManager.shared.onRemotePrevious = nil
    }

    // MARK: - Template building

    private func listTemplate(for language: Language) -> CPListTemplate {
        let units = Curriculum.getUnits(for: language)
        let isOverallUnlocked = UserDefaults.standard.bool(forKey: "vocal_lingo_is_unlocked")
        let firstBeginnerId = units.filter { $0.level == .beginner }.first?.id

        // One CPListSection per difficulty level for a driver-safe scan.
        let sections: [CPListSection] = DifficultyLevel.allCases.compactMap { level in
            let items: [CPListItem] = units
                .filter { $0.level == level }
                .map { unit in
                    let isFree = (unit.id == firstBeginnerId)
                    let isUnlocked = isOverallUnlocked || isFree
                    let title = isUnlocked ? unit.title : "\(unit.title) 🔒"
                    let detail = isUnlocked ? unit.description : "Full Access Required • \(unit.description)"
                    let item = CPListItem(text: title, detailText: detail)
                    item.handler = { [weak self] _, completion in
                        self?.startUnit(unit, language: language)
                        completion()
                    }
                    return item
                }
            guard !items.isEmpty else { return nil }
            return CPListSection(items: items,
                                 header: level.rawValue.uppercased(),
                                 sectionIndexTitle: nil)
        }

        let template = CPListTemplate(title: language.rawValue, sections: sections)
        template.tabTitle = language.rawValue
        template.tabImage = UIImage(systemName: "waveform.circle.fill")
        return template
    }

    // MARK: - Playback flow (mirrors phone-side PracticeView autoplay)

    private func startUnit(_ unit: Unit, language: Language) {
        let baseUnits = Curriculum.getUnits(for: language).filter { $0.level == .beginner }
        let isFree = baseUnits.first?.id == unit.id
        let isUnlocked = UserDefaults.standard.bool(forKey: "vocal_lingo_is_unlocked") || isFree

        guard isUnlocked else {
            print("[CarPlay] Locked unit selected: \(unit.title)")
            let alert = CPAlertTemplate(
                titleVariants: ["Unlock Required", "Please unlock full access on your iPhone to play this lesson."],
                actions: [
                    CPAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
                        self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
                    })
                ]
            )
            interfaceController?.presentTemplate(alert, animated: true, completion: nil)
            return
        }

        print("[CarPlay] startUnit: \(unit.title) [\(language.rawValue)]")
        activeUnit = unit
        activeLanguage = language
        activePhraseIndex = 0

        // Push the Now Playing template so the car screen shows the current
        // phrase with play/pause/skip controls.
        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)

        speakCurrentPhrasePair()
    }

    /// English → target → 3-second repeat window → next phrase.
    private func speakCurrentPhrasePair() {
        guard let unit = activeUnit,
              unit.phrases.indices.contains(activePhraseIndex) else {
            print("[CarPlay] speakCurrentPhrasePair: no unit or out of range")
            return
        }
        let phrase = unit.phrases[activePhraseIndex]

        // 1. English
        VoiceManager.shared.updateNowPlaying(unitTitle: unit.title, phrase: phrase.english)
        VoiceManager.shared.speak(text: phrase.english, localeCode: "en-US", phraseID: phrase.id) { [weak self] in
            guard let self = self, self.activeUnit != nil else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + self.englishToTargetGap) {
                // 2. Target language
                VoiceManager.shared.updateNowPlaying(unitTitle: unit.title, phrase: phrase.translation)
                VoiceManager.shared.speak(text: phrase.translation,
                                          localeCode: self.activeLanguage.localeCode,
                                          phraseID: phrase.id) { [weak self] in
                    guard let self = self, self.activeUnit != nil else { return }

                    // 3. Repeat window
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.targetToRepeatGap) {
                        self.beginRepeatWindow(unit: unit, phrase: phrase)
                    }
                }
            }
        }
    }

    private func beginRepeatWindow(unit: Unit, phrase: Phrase) {
        VoiceManager.shared.updateNowPlaying(unitTitle: unit.title,
                                             phrase: "Repeat: \(phrase.translation)")

        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatWindow, repeats: false) { [weak self] _ in
            guard let self = self, self.activeUnit != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.phraseToPhraseGap) {
                self.advancePhrase(by: 1)
            }
        }
    }

    private func advancePhrase(by delta: Int) {
        guard let unit = activeUnit else { return }
        repeatTimer?.invalidate()
        repeatTimer = nil

        let next = activePhraseIndex + delta
        if next >= unit.phrases.count {
            // End of unit — stop and clear.
            print("[CarPlay] End of unit")
            VoiceManager.shared.stop()
            activeUnit = nil
            return
        }
        if next < 0 {
            activePhraseIndex = 0
        } else {
            activePhraseIndex = next
        }
        speakCurrentPhrasePair()
    }
}

// FILE COMPLETE
