import SwiftUI

public struct HomeView: View {
    @State private var selectedLanguage: Language = .spanish
    @State private var selectedLevel: DifficultyLevel = .beginner
    @State private var activeUnit: Unit? = nil
    @State private var passedUnits: Set<UUID> = []
    @State private var isAutoplayActive: Bool = false
    
    // AI Textbook Generator States
    @State private var customTopicInput: String = ""
    @State private var generatingUnit: Bool = false
    @State private var generationError: String? = nil
    @State private var generatedUnits: [Language: [Unit]] = [:]
    

    private var placeholderText: String {
        switch selectedLanguage {
        case .spanish: return "e.g. Booking a hotel in Madrid..."
        case .french: return "e.g. Navigating a Parisian cafe..."
        case .german: return "e.g. Meeting a business partner..."
        case .japanese: return "e.g. Ordering sushi in Tokyo..."
        }
    }
    
    // Suggestions map matching App.tsx
    private let suggestions: [Language: [DifficultyLevel: [String]]] = [
        .spanish: [
            .beginner: ["Ordering Street Tacos", "Greeting New Friends", "Numbers & Shopping"],
            .intermediate: ["Booking a Rental Car", "Explaining Medical Symptoms", "Ordering in a Restaurant"],
            .expert: ["Business Contract Negotiating", "Expressing Complex Opinions", "Spanish Idioms & Sayings"]
        ],
        .french: [
            .beginner: ["Meeting Neighbors", "Ordering Fresh Croissants", "Asking for Directions"],
            .intermediate: ["Reserving a Train Ticket", "Buying Clothes at a Boutique", "Planning a Dinner Party"],
            .expert: ["Discussing Art & Philosophy", "Job Interview Prep", "French Political Debates"]
        ],
        .german: [
            .beginner: ["Basic Greetings", "Ordering Beer at a Tavern", "Telling the Time"],
            .intermediate: ["Apotheke (Pharmacy) Help", "Renting an Apartment", "Exploring a Museum"],
            .expert: ["Corporate Boardroom Pitch", "Debating Environmental Policy", "Scientific Vocabulary"]
        ],
        .japanese: [
            .beginner: ["Convenience Store Essentials", "Self Introduction", "Asking for Train Station"],
            .intermediate: ["Sushi Bar Etiquette", "Traditional Ryokan Check-in", "Buying Bullet Train Tickets"],
            .expert: ["Formal Keigo Business Meeting", "Discussing Anime & Pop Culture", "Traditional Tea Ceremony"]
        ]
    ]
    
    private var bannerTitle: String {
        switch selectedLevel {
        case .beginner:
            return "BEGINNER MODULES"
        case .intermediate:
            return "INTERMEDIATE MODULES"
        case .expert:
            return "EXPERT MASTERCLASSES"
        }
    }
    
    private var bannerDescription: String {
        switch selectedLevel {
        case .beginner:
            return "Focus on essential key words, simple phrases, and basic grammar structures."
        case .intermediate:
            return "Learn directions, cafés, subway transits, social meetups, and restaurants."
        case .expert:
            return "Master high-level meetings, advanced idioms, professional environments, and expressions."
        }
    }
    
    private var currentBaseUnits: [Unit] {
        Curriculum.getUnits(for: selectedLanguage).filter { $0.level == selectedLevel }
    }
    
    private var currentCustomUnits: [Unit] {
        (generatedUnits[selectedLanguage] ?? []).filter { $0.level == selectedLevel }
    }
    
    private var currentUnits: [Unit] {
        currentBaseUnits + currentCustomUnits
    }
    
    private var currentSuggestions: [String] {
        suggestions[selectedLanguage]?[selectedLevel] ?? []
    }
    
    public init() {}
    
    private func languageButton(lang: Language) -> some View {
        Button(action: {
            selectedLanguage = lang
            activeUnit = nil
        }) {
            HStack(spacing: 8) {
                Text(lang.flag)
                    .font(.system(size: 18))
                Text(lang.rawValue)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                selectedLanguage == lang
                ? Color.blue.opacity(0.25)
                : Color.white.opacity(0.06)
            )
            .foregroundColor(
                selectedLanguage == lang ? .blue : .white
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        selectedLanguage == lang ? Color.blue : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
    }
    
    private var languageSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Language.allCases) { lang in
                    languageButton(lang: lang)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 10)
    }
    
    private func difficultyButton(lvl: DifficultyLevel) -> some View {
        Button(action: {
            selectedLevel = lvl
        }) {
            Text(lvl.rawValue.uppercased())
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(selectedLevel == lvl ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedLevel == lvl ? Color.blue : Color.clear)
                .cornerRadius(10)
        }
    }
    
    private var difficultyTabs: some View {
        HStack(spacing: 4) {
            ForEach(DifficultyLevel.allCases) { lvl in
                difficultyButton(lvl: lvl)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }
    
    private var levelBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .foregroundColor(.blue)
                .font(.system(size: 18))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Text(bannerDescription)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.02))
        .cornerRadius(18)
        .padding(.horizontal, 20)
    }
    
    private func unitRowButton(unit: Unit) -> some View {
        Button(action: {
            activeUnit = unit
        }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(unit.level.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                            .foregroundColor(.gray)
                        
                        if passedUnits.contains(unit.id) {
                            Text("PASSED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(6)
                                .foregroundColor(.green)
                        }
                        
                        if currentCustomUnits.contains(where: { $0.id == unit.id }) {
                            Text("AI GENERATED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(6)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Text(unit.title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(.white)
                    
                    Text(unit.description)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.2))
                    .font(.system(size: 14, weight: .bold))
            }
            .padding(18)
            .background(Color.white.opacity(0.04))
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
    }
    
    private var aiHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.05))
                .padding(.vertical, 8)
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                Text("AI TEXTBOOK GENERATOR")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(1)
            }
            
            Text("Draft a brand new custom chapter instantly. Ask for any scenario, trip setup, or specialized workplace vocabulary.")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.gray)
                .lineLimit(nil)
        }
    }
    
    private var aiInputSection: some View {
        HStack(spacing: 8) {
            TextField(
                placeholderText,
                text: $customTopicInput
            )
            .font(.system(size: 12, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.4))
            .cornerRadius(12)
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .disabled(generatingUnit)
            
            Button(action: {
                generateUnitDraft(topic: customTopicInput)
            }) {
                if generatingUnit {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 54, height: 38)
                        .background(Color.blue.opacity(0.4))
                        .cornerRadius(12)
                } else {
                    Text("Draft")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 38)
                        .background(customTopicInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.05) : Color.blue)
                        .cornerRadius(12)
                }
            }
            .disabled(generatingUnit || customTopicInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    
    private func suggestionButton(topic: String) -> some View {
        Button(action: {
            customTopicInput = topic
            generateUnitDraft(topic: topic)
        }) {
            Text("+ \(topic)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.03))
                .foregroundColor(.gray)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
                )
        }
        .disabled(generatingUnit)
    }
    
    private var aiSuggestionsSection: some View {
        Group {
            if !currentSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(currentSuggestions, id: \.self) { topic in
                            suggestionButton(topic: topic)
                        }
                    }
                }
            }
        }
    }
    
    private func aiErrorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠️ DRAFTING FAILED")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(.red)
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.red.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var aiGeneratorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            aiHeaderSection
            aiInputSection
            aiSuggestionsSection
            if let error = generationError {
                aiErrorSection(error: error)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.02))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Dark slate background
                Color(red: 0.03, green: 0.05, blue: 0.08)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    languageSelector
                    
                    difficultyTabs
                    
                    levelBanner
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(currentUnits) { unit in
                                unitRowButton(unit: unit)
                            }
                            
                            aiGeneratorSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("VocalLingo")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $activeUnit) { unit in
                PracticeView(
                    unit: unit,
                    selectedLanguage: selectedLanguage,
                    isAutoplayActive: $isAutoplayActive,
                    onUnitPassed: {
                        passedUnits.insert(unit.id)
                    },
                    onNextUnit: {
                        advanceToNextUnit()
                    },
                    // v8: return the next unit in the current level (or nil at
                    // the end) so PracticeView can pre-render its audio while
                    // this unit is still playing. Level transitions are not
                    // pre-warmed — they happen rarely enough that the standard
                    // PREP flow is fine.
                    nextUnitLookup: {
                        let baseUnits = Curriculum.getUnits(for: selectedLanguage).filter { $0.level == selectedLevel }
                        let customUnits = (generatedUnits[selectedLanguage] ?? []).filter { $0.level == selectedLevel }
                        let allUnits = baseUnits + customUnits
                        guard let idx = allUnits.firstIndex(where: { $0.id == unit.id }) else { return nil }
                        let nextIndex = idx + 1
                        return nextIndex < allUnits.count ? allUnits[nextIndex] : nil
                    }
                )
            }
        }
    }
    
    /// Continuous autoplay progress controller to load next unit/difficulty level
    private func advanceToNextUnit() {
        guard let currentUnit = activeUnit else { return }
        
        let baseUnits = Curriculum.getUnits(for: selectedLanguage).filter { $0.level == selectedLevel }
        let customUnits = (generatedUnits[selectedLanguage] ?? []).filter { $0.level == selectedLevel }
        let allUnits = baseUnits + customUnits
        
        if let currentIndex = allUnits.firstIndex(where: { $0.id == currentUnit.id }) {
            let nextIndex = currentIndex + 1
            if nextIndex < allUnits.count {
                activeUnit = allUnits[nextIndex]
            } else {
                let nextLevel: DifficultyLevel
                switch selectedLevel {
                case .beginner: nextLevel = .intermediate
                case .intermediate: nextLevel = .expert
                case .expert: nextLevel = .beginner
                }
                selectedLevel = nextLevel
                
                let nextBaseUnits = Curriculum.getUnits(for: selectedLanguage).filter { $0.level == nextLevel }
                let nextCustomUnits = (generatedUnits[selectedLanguage] ?? []).filter { $0.level == nextLevel }
                let nextAllUnits = nextBaseUnits + nextCustomUnits
                
                if let firstUnit = nextAllUnits.first {
                    activeUnit = firstUnit
                } else {
                    isAutoplayActive = false
                    activeUnit = nil
                }
            }
        }
    }
    
    // MARK: - AI unit generation (Apple Intelligence, on-device only)

    /// DTOs matching the JSON schema emitted by
    /// AppleIntelligenceService.generateCurriculumUnit.
    private struct GeneratedPhraseDTO: Decodable {
        let english: String
        let translation: String
        let romanization: String?
        let exampleEnglish: String?
        let exampleTranslation: String?
    }
    private struct GeneratedUnitDTO: Decodable {
        let title: String
        let description: String
        let phrases: [GeneratedPhraseDTO]
    }

    /// Triggers dynamic unit drafting via on-device Apple Intelligence
    /// Foundation Models. Falls back to the local mock ONLY when the framework
    /// is unavailable on this device (e.g. iOS 17 simulator, Apple Intelligence
    /// disabled, model still downloading) so development on non-AI hardware
    /// keeps working. No network calls, no external APIs.
    private func generateUnitDraft(topic: String) {
        generationError = nil
        generatingUnit = true

        let availability = AppleIntelligenceService.shared.availability()
        guard availability.isAvailable else {
            // Non-AI device path: keep the app usable with the local mock and
            // surface the reason so the user understands why real generation
            // was skipped.
            generationError = availability.reason
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                appendMockUnit(topic: topic)
                generatingUnit = false
            }
            return
        }

        AppleIntelligenceService.shared.generateCurriculumUnit(
            topic: topic,
            language: selectedLanguage.rawValue,
            level: selectedLevel.rawValue
        ) { result in
            DispatchQueue.main.async {
                generatingUnit = false
                switch result {
                case .success(let json):
                    do {
                        guard let data = json.data(using: .utf8) else {
                            generationError = "Apple Intelligence returned an empty response."
                            return
                        }
                        let dto = try JSONDecoder().decode(GeneratedUnitDTO.self, from: data)
                        let unit = Unit(
                            title: dto.title.isEmpty ? topic : dto.title,
                            description: dto.description.isEmpty
                                ? "Custom hands-free textbook covering \"\(topic)\". Optimized for car practice."
                                : dto.description,
                            level: selectedLevel,
                            phrases: dto.phrases.map { p in
                                Phrase(
                                    english: p.english,
                                    translation: p.translation,
                                    romanization: (p.romanization?.isEmpty ?? true) ? nil : p.romanization,
                                    exampleEnglish: p.exampleEnglish,
                                    exampleTranslation: p.exampleTranslation
                                )
                            }
                        )
                        var currentCustom = generatedUnits[selectedLanguage] ?? []
                        currentCustom.append(unit)
                        generatedUnits[selectedLanguage] = currentCustom
                        customTopicInput = ""
                    } catch {
                        generationError = "Could not parse the generated lesson: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    generationError = error.localizedDescription
                }
            }
        }
    }

    /// Development fallback: appends a hard-coded 4-phrase unit so the app
    /// still works on devices without Apple Intelligence.
    private func appendMockUnit(topic: String) {
        let mockUnit = generateLocalMockUnit(topic: topic, language: selectedLanguage, level: selectedLevel)
        var currentCustom = generatedUnits[selectedLanguage] ?? []
        currentCustom.append(mockUnit)
        generatedUnits[selectedLanguage] = currentCustom
        customTopicInput = ""
    }

    /// Instant on-device localized premium text generator matching selected parameters.
    /// Kept only as a fallback when Apple Intelligence is unavailable on the device.
    private func generateLocalMockUnit(topic: String, language: Language, level: DifficultyLevel) -> Unit {
        var phrases: [Phrase] = []
        if language == .spanish {
            phrases = [
                Phrase(english: "Where is the station?", translation: "¿Dónde está la estación?", romanization: "Dohn-deh ehs-tah lah ehs-tah-syohn?", exampleEnglish: "Excuse me, where is the train station?", exampleTranslation: "Disculpe, ¿dónde está la estación de tren?"),
                Phrase(english: "Could you help me, please?", translation: "¿Me podría ayudar, por favor?", romanization: "Meh poh-dree-ah ah-yoo-dahr pohr fah-vohr?", exampleEnglish: "Could you help me open this door?", exampleTranslation: "¿Me podría ayudar a abrir esta puerta, por favor?"),
                Phrase(english: "I am ready to practice.", translation: "Estoy listo para practicar.", romanization: "Ehs-toy lees-toh pah-rah prahk-tee-cahr.", exampleEnglish: "I am ready to practice speaking Spanish now.", exampleTranslation: "Estoy listo para practicar hablar español ahora."),
                Phrase(english: "Thank you for teaching me.", translation: "Gracias por enseñarme.", romanization: "Grah-syahs pohr ehn-sehn-yahr-meh.", exampleEnglish: "Thank you for teaching me how to say this phrase.", exampleTranslation: "Gracias por enseñarme cómo decir esta frase.")
            ]
        } else if language == .french {
            phrases = [
                Phrase(english: "Where is the exit?", translation: "Où est la sortie ?", romanization: "Oo eh lah sor-tee?", exampleEnglish: "Excuse me, where is the terminal exit?", exampleTranslation: "Excusez-moi, où est la sortie du terminal ?"),
                Phrase(english: "How do you say this?", translation: "Comment dit-on cela ?", romanization: "Kom-mahn dee-tohn suh-lah?", exampleEnglish: "How do you say this in French?", exampleTranslation: "Comment dit-on cela en français ?"),
                Phrase(english: "I understand.", translation: "Je comprends.", romanization: "Zheh kohm-prahn.", exampleEnglish: "Ah, I understand what you mean.", exampleTranslation: "Ah, je comprends ce que vous voulez dire."),
                Phrase(english: "Have a beautiful day!", translation: "Passez une belle journée !", romanization: "Pah-say oon bell zhoor-nay!", exampleEnglish: "Thank you very much, have a beautiful day!", exampleTranslation: "Merci beaucoup, passez une belle journée !")
            ]
        } else if language == .japanese {
            phrases = [
                Phrase(english: "Where is the convenience store?", translation: "コンビニはどこですか？", romanization: "Kombini wa doko desu ka?", exampleEnglish: "Excuse me, where is the nearest convenience store?", exampleTranslation: "Sumimasen, chikaku no kombini wa doko desu ka?"),
                Phrase(english: "I am looking for this key.", translation: "この鍵を探しています。", romanization: "Kono kagi o sagashite imasu.", exampleEnglish: "Pardon me, I am looking for this car key.", exampleTranslation: "Sumimasen, kono kagi o sagashite imasu."),
                Phrase(english: "Nice to meet you.", translation: "はじめまして、よろしくお願いします。", romanization: "Hajimemashite, yoroshiku onegai shimasu.", exampleEnglish: "Nice to meet you, I am looking forward to our trip.", exampleTranslation: "Hajimemashite, yoroshiku onegai shimasu. Ryokou o tanoshimi ni shiteimasu."),
                Phrase(english: "Thank you very much.", translation: "どうもありがとうございました。", romanization: "Doumo arigatou gozaimashita.", exampleEnglish: "Thank you very much for your great advice.", exampleTranslation: "Ii adobaisu o arigatou gozaimashita.")
            ]
        } else { // German
            phrases = [
                Phrase(english: "Where is the next cafe?", translation: "Wo ist das nächste Café?", romanization: "Voh ist dahs nekhst-eh ka-fay?", exampleEnglish: "Excuse me, where is the next cafe nearby?", exampleTranslation: "Entschuldigung, wo ist das nächste Café in der Nähe?"),
                Phrase(english: "Can you help me with this?", translation: "Können Sie mir dabei helfen?", romanization: "Keon-nen zee meer dah-by hel-fen?", exampleEnglish: "Pardon, can you help me with this luggage?", exampleTranslation: "Entschuldigung, können Sie mir bei diesem Gepäck helfen?"),
                Phrase(english: "I am ready for the test.", translation: "Ich bin bereit für den Test.", romanization: "Ikh bin beh-ryte feur dane test.", exampleEnglish: "Yes, I am ready for the certification test.", exampleTranslation: "Ja, ich bin bereit für den Zertifizierungstest."),
                Phrase(english: "Have a wonderful trip!", translation: "Haben Sie eine wunderbare Reise!", romanization: "Hah-ben zee eye-neh voon-der-bah-reh rye-zeh!", exampleEnglish: "Goodbye, have a wonderful trip!", exampleTranslation: "Auf Wiedersehen, haben Sie eine wunderbare Reise!")
            ]
        }
        
        return Unit(
            title: topic,
            description: "Custom hands-free textbook covering \"\(topic)\". Optimized for car practice.",
            level: level,
            phrases: phrases
        )
    }
}

// FILE COMPLETE