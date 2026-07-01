//
//  FlashcardStore.swift
//  ITBizEnglish
//
//  Lightweight persistence for saved flashcards + recent translation history.
//  Backed by UserDefaults (JSON) so it has zero external dependencies.
//  Swap for SwiftData / Core Data later without touching the views.
//

import Foundation
import Observation

/// A single saved flashcard. We persist the whole result plus which tone
/// the user chose to save, so the flashcard can show the right English side.
struct Flashcard: Codable, Identifiable, Hashable {
    let id: String
    let vietnameseText: String
    let english: String
    let tone: String          // Tone.rawValue
    let tags: [String]
    let savedAt: Date

    init(result: TranslationResult, tone: Tone) {
        self.id = result.id + "-" + tone.rawValue
        self.vietnameseText = result.vietnameseText
        self.english = tone.text(from: result.englishOptions)
        self.tone = tone.rawValue
        self.tags = result.tags
        self.savedAt = .now
    }
}

@Observable
final class FlashcardStore {
    private(set) var flashcards: [Flashcard] = []
    private(set) var history: [TranslationResult] = []

    private let flashcardsKey = "itbiz.flashcards.v1"
    private let historyKey = "itbiz.history.v1"
    private let maxHistory = 25

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Flashcards

    func isSaved(_ result: TranslationResult, tone: Tone) -> Bool {
        let cardID = result.id + "-" + tone.rawValue
        return flashcards.contains { $0.id == cardID }
    }

    /// Toggles save state. Returns the new state (`true` == saved).
    @discardableResult
    func toggleFlashcard(_ result: TranslationResult, tone: Tone) -> Bool {
        let card = Flashcard(result: result, tone: tone)
        if let idx = flashcards.firstIndex(where: { $0.id == card.id }) {
            flashcards.remove(at: idx)
            persistFlashcards()
            return false
        } else {
            flashcards.insert(card, at: 0)
            persistFlashcards()
            return true
        }
    }

    func deleteFlashcards(at offsets: IndexSet) {
        flashcards.remove(atOffsets: offsets)
        persistFlashcards()
    }

    // MARK: - History

    func addToHistory(_ result: TranslationResult) {
        history.removeAll { $0.vietnameseText == result.vietnameseText }
        history.insert(result, at: 0)
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    /// Replaces saved flashcards + translation history (backup import) and persists.
    func restore(flashcards: [Flashcard], history: [TranslationResult]) {
        self.flashcards = flashcards
        self.history = history
        persistFlashcards()
        persistHistory()
    }

    // MARK: - Persistence

    private func persistFlashcards() {
        if let data = try? JSONEncoder().encode(flashcards) {
            defaults.set(data, forKey: flashcardsKey)
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: flashcardsKey),
           let decoded = try? JSONDecoder().decode([Flashcard].self, from: data) {
            flashcards = decoded
        }
        if let data = defaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([TranslationResult].self, from: data) {
            history = decoded
        }
    }
}
