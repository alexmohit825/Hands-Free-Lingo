import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Errors raised by the on-device Apple Intelligence pipeline.
public enum AppleIntelligenceError: LocalizedError {
    case frameworkUnavailable
    case modelUnavailable(reason: String)
    case generationFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "Apple Intelligence Foundation Models are only available on iOS 26 (iOS 18.1+ preview builds) and later. Update your device or OS to generate new lessons."
        case .modelUnavailable(let reason):
            return "Apple Intelligence is not currently available on this device: \(reason)"
        case .generationFailed(let underlying):
            return "Apple Intelligence could not generate this lesson: \(underlying.localizedDescription)"
        }
    }
}

/// Primary and only Apple Intelligence On-Device Foundation Models Service.
/// Powered by Apple Intelligence on iOS 18.1+ / macOS Sequoia+. There is no
/// cloud fallback: if the device cannot run the on-device model, the caller
/// receives a typed AppleIntelligenceError.
public final class AppleIntelligenceService {
    public static let shared = AppleIntelligenceService()

    private init() {}

    /// Reports whether the on-device Foundation Model is ready for use, plus a
    /// human-readable reason when it is not.
    public struct Availability {
        public let isAvailable: Bool
        public let reason: String?
    }

    public func availability() -> Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return Availability(isAvailable: true, reason: nil)
            }
            let detail: String
            switch model.availability {
            case .available:
                detail = "Ready."
            case .unavailable(.deviceNotEligible):
                detail = "This device is not eligible for Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                detail = "Apple Intelligence is turned off in Settings."
            case .unavailable(.modelNotReady):
                detail = "The on-device model is still downloading. Please try again shortly."
            case .unavailable(let other):
                detail = "Unavailable: \(other)."
            }
            return Availability(isAvailable: false, reason: detail)
        } else {
            return Availability(isAvailable: false, reason: "Requires iOS 26 or later.")
        }
        #else
        return Availability(isAvailable: false, reason: "FoundationModels framework not linked in this build.")
        #endif
    }

    /// Generates a curriculum unit natively using Apple Intelligence on-device
    /// Foundation Models. Returns the raw JSON payload as a string so the
    /// caller can decode it with the existing CurriculumUnit models.
    public func generateCurriculumUnit(
        topic: String,
        language: String,
        level: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, macCatalyst 26.0, *) {
            let availability = self.availability()
            guard availability.isAvailable else {
                completion(.failure(AppleIntelligenceError.modelUnavailable(reason: availability.reason ?? "Unknown reason.")))
                return
            }

            Task {
                do {
                    let instructions = """
                    You are Native Tongue, an on-device language tutor. Generate one \(language) study unit at the \(level) level focused on the topic: \(topic).

                    Return ONLY valid JSON matching exactly this schema, with no prose before or after:
                    {
                      "title": "<short unit title in English>",
                      "description": "<one-sentence English description>",
                      "phrases": [
                        {
                          "english": "<English phrase>",
                          "translation": "<translation in \(language)>",
                          "romanization": "<romanization if the target script is non-Latin, otherwise empty string>",
                          "exampleEnglish": "<full example English sentence using the phrase>",
                          "exampleTranslation": "<same example sentence translated into \(language)>"
                        }
                      ]
                    }

                    Generate 9 phrases. Keep every translation natural, culturally appropriate, and safe for a general audience. Do not include markdown, code fences, or commentary.
                    """

                    let session = LanguageModelSession(instructions: Instructions(instructions))
                    let response = try await session.respond(to: "Generate the JSON now.")
                    let raw = response.content

                    // The model may occasionally wrap the JSON in code fences; strip them.
                    let trimmed = Self.stripCodeFences(raw)
                    completion(.success(trimmed))
                } catch {
                    completion(.failure(AppleIntelligenceError.generationFailed(underlying: error)))
                }
            }
        } else {
            completion(.failure(AppleIntelligenceError.frameworkUnavailable))
        }
        #else
        completion(.failure(AppleIntelligenceError.frameworkUnavailable))
        #endif
    }

    /// Streaming variant for callers that want to render partial output as it
    /// arrives (used by the practice view's live-feedback UI).
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, macCatalyst 26.0, *)
    public func streamCurriculumUnit(
        topic: String,
        language: String,
        level: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let availability = self.availability()
            guard availability.isAvailable else {
                continuation.finish(throwing: AppleIntelligenceError.modelUnavailable(reason: availability.reason ?? "Unknown reason."))
                return
            }
            Task {
                do {
                    let instructions = """
                    You are Native Tongue, an on-device language tutor. Generate one \(language) study unit at the \(level) level focused on: \(topic).
                    Respond with the JSON schema requested by the caller. Nine phrases. No prose.
                    """
                    let session = LanguageModelSession(instructions: Instructions(instructions))
                    let stream = session.streamResponse(to: "Generate the JSON now.")
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AppleIntelligenceError.generationFailed(underlying: error))
                }
            }
        }
    }
    #endif

    /// Removes triple-backtick JSON fences that the on-device model sometimes emits.
    private static func stripCodeFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fence = "```"
        if s.hasPrefix(fence) {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
        }
        if s.hasSuffix(fence) {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// FILE COMPLETE