//
//  SentenceCheckService.swift
//  ITBizEnglish
//
//  Uses Gemini to evaluate the user's English rendering of a Vietnamese
//  sentence. The reference answer (if any) is just a hint — the AI accepts any
//  correct, natural phrasing and points out specific issues to fix.
//

import Foundation

struct SentenceCheckService {

    private let systemPrompt = """
    You are a friendly IT/Business English SPEAKING coach for a Vietnamese frontend developer.
    The user is practicing speaking by translating a Vietnamese sentence into English themselves.
    Treat their attempt as something said out loud, NOT a written sentence.
    Evaluate the user's English attempt:
    - Accept ANY correct and natural phrasing. The provided reference (if any) is only a hint, NOT the required answer.
    - Judge meaning accuracy, grammar, word choice, naturalness, and workplace tone — as if spoken.
    - IGNORE writing-only conventions completely: do NOT lower the score for and do NOT mention
      capitalization, punctuation, or trailing periods. Read everything case-insensitively.
    - Be encouraging but specific.
    Respond ONLY with raw JSON (no markdown), matching:
    {
      "score": 0-100 integer (how well the attempt conveys the meaning naturally when spoken; never deduct for capitalization or punctuation),
      "verdict": short label like "Perfect", "Natural", "Understandable", or "Needs work",
      "correctedVersion": the best natural English version (keep the user's wording if already good),
      "notes": array of short, specific fixes in Vietnamese about meaning/grammar/word choice only — never about capitalization or punctuation (empty array if the attempt is already great)
    }
    """

    func check(vietnamese: String, attempt: String, reference: String) async throws -> AIFeedback {
        let trimmedAttempt = attempt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAttempt.isEmpty else { throw TranslationError.emptyInput }

        var userText = """
        Vietnamese sentence: "\(vietnamese)"
        User's English attempt: "\(trimmedAttempt)"
        """
        if !reference.trimmingCharacters(in: .whitespaces).isEmpty {
            userText += "\nReference hint (not the only correct answer): \"\(reference)\""
        }

        let content = try await LLMClient.generateJSON(system: systemPrompt, user: userText, temperature: 0.3)
        return try decode(content)
    }

    // MARK: - Decode

    private struct Payload: Decodable {
        let score: Int
        let verdict: String
        let correctedVersion: String
        let notes: [String]
    }

    private func decode(_ content: String) throws -> AIFeedback {
        guard let jsonData = content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: jsonData) else {
            throw TranslationError.decoding
        }
        return AIFeedback(
            score: max(0, min(100, payload.score)),
            verdict: payload.verdict,
            correctedVersion: payload.correctedVersion,
            notes: payload.notes
        )
    }
}
