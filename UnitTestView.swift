import SwiftUI

struct QuizQuestion: Identifiable {
    let id = UUID()
    let type: String // translation, multiple-choice, listening
    let prompt: String
    let correctOption: String
    let options: [String]
    let phrase: Phrase
}

public struct UnitTestView: View {
    @Environment(\.dismiss) private var dismiss
    
    let unit: Unit
    let selectedLanguage: Language
    let onPass: () -> Void
    
    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex: Int = 0
    @State private var selectedOption: String? = nil
    @State private var testScore: Int = 0
    @State private var isCompleted: Bool = false
    @StateObject private var voiceManager = VoiceManager.shared
    
    public init(unit: Unit, selectedLanguage: Language, onPass: @escaping () -> Void) {
        self.unit = unit
        self.selectedLanguage = selectedLanguage
        self.onPass = onPass
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.05, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header Bar
                HStack {
                    Text("Unit Certification Test")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.black)
                        .foregroundColor(.gray)
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                if !isCompleted {
                    if !questions.isEmpty {
                        let currentQ = questions[currentIndex]
                        
                        VStack(spacing: 20) {
                            // Progress bar
                            HStack {
                                Text("QUESTION \(currentIndex + 1) OF 5")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                Spacer()
                                ProgressView(value: Double(currentIndex + 1), total: 5.0)
                                    .frame(width: 80)
                            }
                            .padding(.horizontal, 20)
                            
                            // Question Card
                            VStack(spacing: 16) {
                                if currentQ.type == "listening" {
                                    VStack(spacing: 10) {
                                        Image(systemName: "speaker.wave.3.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.blue)
                                            .padding()
                                            .background(Circle().fill(Color.blue.opacity(0.1)))
                                        
                                        Button(action: {
                                            voiceManager.speak(text: currentQ.phrase.translation, localeCode: selectedLanguage.localeCode)
                                        }) {
                                            Text("Play Spoken Audio")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                
                                Text(currentQ.prompt)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(24)
                            .padding(.horizontal, 20)
                            
                            // Options
                            VStack(spacing: 10) {
                                ForEach(currentQ.options, id: \.self) { option in
                                    Button(action: {
                                        selectedOption = option
                                    }) {
                                        HStack {
                                            Text(option)
                                                .font(.system(.subheadline, design: .rounded))
                                                .fontWeight(.bold)
                                            Spacer()
                                            Circle()
                                                .stroke(selectedOption == option ? Color.blue : Color.gray, lineWidth: 2)
                                                .frame(width: 16, height: 16)
                                                .overlay(
                                                    Circle()
                                                        .fill(selectedOption == option ? Color.blue : Color.clear)
                                                        .frame(width: 8, height: 8)
                                                )
                                        }
                                        .padding(16)
                                        .background(selectedOption == option ? Color.blue.opacity(0.12) : Color.white.opacity(0.03))
                                        .foregroundColor(selectedOption == option ? .blue : .white)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(selectedOption == option ? Color.blue : Color.clear, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            Spacer()
                            
                            // Submit action
                            Button(action: {
                                nextStep()
                            }) {
                                Text(currentIndex == 4 ? "FINISH TEST" : "NEXT QUESTION")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(selectedOption == nil ? Color.gray.opacity(0.3) : Color.blue)
                                    .cornerRadius(18)
                            }
                            .disabled(selectedOption == nil)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        }
                    }
                } else {
                    // Result Screen
                    VStack(spacing: 24) {
                        Spacer()
                        
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 60))
                            .foregroundColor(testScore >= 80 ? .yellow : .gray)
                        
                        Text("Test Completed")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                        
                        VStack(spacing: 8) {
                            Text("YOUR GRADE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text("\(testScore)%")
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            
                            if testScore >= 80 {
                                Text("UNIT CERTIFIED PASSED")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(8)
                            } else {
                                Text("Score 80% or more to pass.")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(24)
                        .padding(.horizontal, 20)
                        
                        Spacer()
                        
                        Button(action: {
                            dismiss()
                        }) {
                            Text("DONE")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(18)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .onAppear {
            generateQuestions()
        }
    }
    
    private func generateQuestions() {
        let phrases = unit.phrases
        var list: [QuizQuestion] = []
        
        for i in 0..<5 {
            let phrase = phrases[i % phrases.count]
            let type = i % 3 == 0 ? "translation" : (i % 3 == 1 ? "multiple-choice" : "listening")
            
            let distractors = phrases.filter { $0.id != phrase.id }.shuffled().prefix(3)
            var options: [String] = []
            var prompt = ""
            var correctOption = ""
            
            if type == "translation" {
                prompt = "What does \"\(phrase.translation)\" mean in English?"
                correctOption = phrase.english
                options = ([phrase.english] + distractors.map { $0.english }).shuffled()
            } else if type == "multiple-choice" {
                prompt = "How do you say \"\(phrase.english)\" in \(selectedLanguage.rawValue)?"
                correctOption = phrase.translation
                options = ([phrase.translation] + distractors.map { $0.translation }).shuffled()
            } else {
                prompt = "Listen to the audio and select the correct English translation."
                correctOption = phrase.english
                options = ([phrase.english] + distractors.map { $0.english }).shuffled()
            }
            
            list.append(QuizQuestion(type: type, prompt: prompt, correctOption: correctOption, options: options, phrase: phrase))
        }
        
        self.questions = list
        
        if list[0].type == "listening" {
            voiceManager.speak(text: list[0].phrase.translation, localeCode: selectedLanguage.localeCode)
        }
    }
    
    private func nextStep() {
        guard let sel = selectedOption else { return }
        let currentQ = questions[currentIndex]
        
        if sel == currentQ.correctOption {
            testScore += 20
        }
        
        selectedOption = nil
        
        if currentIndex < 4 {
            currentIndex += 1
            let nextQ = questions[currentIndex]
            if nextQ.type == "listening" {
                voiceManager.speak(text: nextQ.phrase.translation, localeCode: selectedLanguage.localeCode)
            }
        } else {
            if testScore >= 80 {
                onPass()
            }
            isCompleted = true
        }
    }
}

// FILE COMPLETE