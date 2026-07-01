//
//  DeckAIService.swift
//  ITBizEnglish
//
//  Uses Gemini to expand a simple list of words/phrases into full DeckWord
//  entries (Vietnamese meaning, IPA pronunciation, example sentence) — so the
//  user can add vocabulary with AI instead of typing every field.
//
//  Reuses the same free Gemini key from Configuration.plist (AppConfiguration).
//

import Foundation

struct DeckAIService {

    private func systemPrompt(includeBaseForms: Bool) -> String {
        var prompt = """
        You are an expert lexicographer building IT/Business English flashcards for a Vietnamese frontend developer.
        For each input term (an English word/phrase, OR a Vietnamese word/phrase), produce one flashcard entry.
        - "word": the natural English term (translate to English if the input is Vietnamese).
        - "meaning": a VERY short Vietnamese gloss — just 1 to 5 words, enough to grasp the term. NOT a full sentence or a detailed/wordy explanation.
        - "pronunciation": IPA for the English word (e.g. "/dɪˈplɔɪ/").
        - "example": one natural English example sentence in an IT/workplace context.
        - "partOfSpeech": a SHORT Vietnamese part-of-speech label, e.g. "động từ", "danh từ", "tính từ", "trạng từ", "cụm danh từ", "cụm động từ".
        """
        if includeBaseForms {
            prompt += """

            IMPORTANT: If an English term is an INFLECTED form (plural, gerund/-ing, past tense, comparative, etc.),
            output TWO items: one for the term exactly as given, and one for its BASE / dictionary form — each a full,
            independent flashcard. Example: input "investigating" → one item for "investigating" AND one for "investigate".
            If the term is already in base form, output just one item.
            """
        }
        prompt += """

        Respond ONLY with a raw JSON object of the form {"items": [{"word": "...", "meaning": "...", "pronunciation": "...", "example": "...", "partOfSpeech": "..."}]}. No markdown fences, no extra text.
        """
        return prompt
    }

    /// Expands raw lines (one term per line) into full DeckWords.
    ///
    /// - Parameter includeBaseForms: when true, an inflected term also yields a
    ///   separate flashcard for its base/dictionary form (used by quick lookup,
    ///   where the user saves a single word). Bulk paths leave this off so a long
    ///   list doesn't silently double in size.
    func generateWords(from rawText: String, includeBaseForms: Bool = false) async throws -> [DeckWord] {
        let terms = rawText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { throw TranslationError.emptyInput }

        let userText = "Create one flashcard for each of these terms:\n" + terms.joined(separator: "\n")
        let content = try await LLMClient.generateJSON(system: systemPrompt(includeBaseForms: includeBaseForms),
                                                       user: userText, temperature: 0.4)
        return try decode(content)
    }

    // MARK: - Decode

    private struct Wrapper: Decodable { let items: [Row] }
    private struct Row: Decodable {
        let word: String
        let meaning: String
        let pronunciation: String?
        let example: String?
        let partOfSpeech: String?
    }

    private func decode(_ content: String) throws -> [DeckWord] {
        guard let jsonData = content.data(using: .utf8),
              let rows = try? JSONDecoder().decode(Wrapper.self, from: jsonData).items else {
            throw TranslationError.decoding
        }
        let words = rows.compactMap { row -> DeckWord? in
            let w = row.word.trimmingCharacters(in: .whitespaces)
            let m = row.meaning.trimmingCharacters(in: .whitespaces)
            guard !w.isEmpty, !m.isEmpty else { return nil }
            let pos = row.partOfSpeech?.trimmingCharacters(in: .whitespaces)
            return DeckWord(word: w, meaning: m,
                            pronunciation: row.pronunciation ?? "",
                            example: row.example ?? "",
                            partOfSpeech: (pos?.isEmpty == false) ? pos : nil)
        }
        guard !words.isEmpty else { throw TranslationError.decoding }
        return words
    }
}
