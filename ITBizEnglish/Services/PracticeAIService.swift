//
//  PracticeAIService.swift
//  ITBizEnglish
//
//  Uses Gemini to generate a batch of Vietnamese practice sentences (with an
//  English reference hint) for the Self-Translate feature — so the user can
//  fill a set with realistic workplace sentences instead of typing each one.
//
//  Reuses the same free Gemini key from Configuration.plist (AppConfiguration).
//

import Foundation

struct PracticeAIService {

    private let systemPrompt = """
    You generate Vietnamese sentences for a Vietnamese frontend developer to practice translating into English, in an IT / business workplace context (standups, code review, planning, meetings, messages to teammates).
    For each item produce:
    - "vietnamese": a natural Vietnamese sentence the developer might actually say or write at work.
    - "english": a natural, professional English translation — used ONLY as a reference hint.
    Make the sentences varied in length and intent. Avoid duplicates.
    Respond ONLY with a raw JSON object of the form {"items": [{"vietnamese": "...", "english": "..."}]}. No markdown fences, no extra text.
    """

    /// Generates `count` practice sentences about `topic`.
    func generateSentences(topic: String, count: Int) async throws -> [PracticeSentence] {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = min(max(count, 1), 30)

        let userText: String
        if trimmedTopic.isEmpty {
            userText = "Generate \(n) varied IT/workplace practice sentences."
        } else {
            userText = "Topic / context: \(trimmedTopic).\nGenerate \(n) practice sentences about this."
        }

        let content = try await LLMClient.generateJSON(system: systemPrompt, user: userText, temperature: 0.9)
        return try decode(content)
    }

    // MARK: - Decode

    private struct Wrapper: Decodable { let items: [Row] }
    private struct Row: Decodable {
        let vietnamese: String
        let english: String?
    }

    private func decode(_ content: String) throws -> [PracticeSentence] {
        guard let jsonData = content.data(using: .utf8),
              let rows = try? JSONDecoder().decode(Wrapper.self, from: jsonData).items else {
            throw TranslationError.decoding
        }
        let sentences = rows.compactMap { row -> PracticeSentence? in
            let vi = row.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vi.isEmpty else { return nil }
            return PracticeSentence(
                vietnamese: vi,
                referenceEnglish: (row.english ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !sentences.isEmpty else { throw TranslationError.decoding }
        return sentences
    }
}
