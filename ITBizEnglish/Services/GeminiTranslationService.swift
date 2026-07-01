//
//  GeminiTranslationService.swift
//  ITBizEnglish
//
//  Real translation powered by Google's Gemini API (free tier). Sends the
//  Vietnamese sentence to gemini-2.5-flash with a system instruction that
//  pins the response to our JSON schema, then decodes it into a
//  TranslationResult. Conforms to `TranslationServicing`, so the rest of the
//  app (TranslationViewModel) doesn't change.
//
//  Setup: the app ships no built-in key. The user adds their own free key on
//  the onboarding gate (first launch) or in Settings ▸ Thêm key — the in-app
//  guide walks them through getting one at https://aistudio.google.com/apikey
//

import Foundation

struct GeminiTranslationService: TranslationServicing {

    /// System instruction that forces a clean, JSON-only response.
private let systemPrompt = """
You are an expert AI Translator specialized in Information Technology (IT) and Corporate Business English for a Frontend Developer.

Task: Translate the user's Vietnamese software development sentence into natural, professional English.

You MUST strictly respond in a raw, valid JSON object only. 
CRITICAL: Do not wrap the JSON in markdown code blocks like ```json ... ```. Do not include any explanations, introduction, or extra text outside the JSON object.

The JSON structure must strictly follow this schema:
{
  "vietnameseText": "string",
  "englishOptions": {
    "casual": "string",
    "professional": "string"
  },
  "tags": ["string"]
}

Context for fields:
- "casual": Natural, concise English for Slack/Teams chat with close teammates.
- "professional": Polished, formal English for Scrum meetings, emails, or talking to stakeholders.
- "tags": An array of 2-4 short technical or situational tags (e.g., "Scrum", "UI/UX", "Bug", "Performance").
"""

    // MARK: - TranslationServicing

    func translate(_ vietnameseText: String) async throws -> TranslationResult {
        let trimmed = vietnameseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        let content = try await LLMClient.generateJSON(system: systemPrompt, user: trimmed, temperature: 0.7)
        return try decodeResult(fromContent: content, originalText: trimmed)
    }

    // MARK: - Response decoding

    private func decodeResult(fromContent content: String, originalText: String) throws -> TranslationResult {
        guard let jsonData = content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TranslationPayload.self, from: jsonData) else {
            throw TranslationError.decoding
        }
        return TranslationResult(
            id: UUID().uuidString,
            vietnameseText: originalText,   // trust our own input over the echo
            englishOptions: EnglishOptions(
                casual: payload.englishOptions.casual,
                professional: payload.englishOptions.professional
            ),
            tags: payload.tags
        )
    }
}

// MARK: - Wire models

/// The JSON our system prompt asks the model to return.
private struct TranslationPayload: Decodable {
    let vietnameseText: String?
    let englishOptions: EnglishOptions
    let tags: [String]
}
