//
//  PracticeStore.swift
//  ITBizEnglish
//
//  Source of truth for Self-Translate practice sets. Persists to a JSON file.
//  Stores cached AI feedback so checked sentences don't need re-evaluation.
//

import Foundation
import Observation

@Observable
final class PracticeStore {
    private(set) var sets: [PracticeSet] = []

    private let filename = "practice.v1.json"
    private let seededKey = "itbiz.practice.seeded.v1"
    /// Set that "Save" from the Translator drops sentences into.
    private let savedSetTitle = "Saved from Translator"

    init() {
        load()
        seedIfNeeded()
    }

    // MARK: - Sets

    func set(id: UUID) -> PracticeSet? { sets.first { $0.id == id } }

    @discardableResult
    func createSet(title: String) -> PracticeSet {
        let s = PracticeSet(title: title.trimmingCharacters(in: .whitespaces), sentences: [])
        sets.insert(s, at: 0)
        persist()
        return s
    }

    func renameSet(id: UUID, to title: String) {
        guard let i = setIndex(id) else { return }
        sets[i].title = title
        persist()
    }

    func setAppearance(icon: String, colorHex: UInt32, forSet id: UUID) {
        guard let i = setIndex(id) else { return }
        sets[i].icon = icon
        sets[i].colorHex = colorHex
        persist()
    }

    func deleteSet(id: UUID) {
        sets.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Sentences

    func addSentence(_ sentence: PracticeSentence, toSet id: UUID) {
        guard let i = setIndex(id) else { return }
        sets[i].sentences.insert(sentence, at: 0)
        persist()
    }

    /// Bulk-adds sentences (e.g. an AI-generated batch the user reviewed),
    /// preserving their order at the top of the set.
    func addSentences(_ sentences: [PracticeSentence], toSet id: UUID) {
        guard !sentences.isEmpty, let i = setIndex(id) else { return }
        sets[i].sentences.insert(contentsOf: sentences, at: 0)
        persist()
    }

    func updateSentence(_ sentence: PracticeSentence, inSet setID: UUID) {
        guard let si = setIndex(setID),
              let wi = sets[si].sentences.firstIndex(where: { $0.id == sentence.id }) else { return }
        sets[si].sentences[wi] = sentence
        persist()
    }

    func deleteSentence(_ sentenceID: UUID, fromSet setID: UUID) {
        guard let si = setIndex(setID) else { return }
        sets[si].sentences.removeAll { $0.id == sentenceID }
        persist()
    }

    /// Flips the "hard" flag on a sentence and returns its new state.
    @discardableResult
    func toggleDifficult(forSentence sentenceID: UUID, inSet setID: UUID) -> Bool {
        guard let si = setIndex(setID),
              let wi = sets[si].sentences.firstIndex(where: { $0.id == sentenceID }) else { return false }
        sets[si].sentences[wi].isDifficult.toggle()
        persist()
        return sets[si].sentences[wi].isDifficult
    }

    /// Records an attempt + its cached AI feedback.
    func saveFeedback(_ feedback: AIFeedback, attempt: String,
                      forSentence sentenceID: UUID, inSet setID: UUID) {
        guard let si = setIndex(setID),
              let wi = sets[si].sentences.firstIndex(where: { $0.id == sentenceID }) else { return }
        sets[si].sentences[wi].lastAttempt = attempt
        sets[si].sentences[wi].feedback = feedback
        persist()
    }

    // MARK: - Sessions

    /// Archives the current session's attempts into each sentence's history,
    /// clears the live attempt/feedback, and bumps the session number so the
    /// user can practice the whole set again from scratch. Old results are kept.
    func startNewSession(forSet setID: UUID) {
        guard let si = setIndex(setID) else { return }
        let session = sets[si].session
        for wi in sets[si].sentences.indices {
            let s = sets[si].sentences[wi]
            if s.feedback != nil || !s.lastAttempt.trimmingCharacters(in: .whitespaces).isEmpty {
                sets[si].sentences[wi].history.append(
                    PracticeAttempt(session: session, attempt: s.lastAttempt, feedback: s.feedback)
                )
            }
            sets[si].sentences[wi].lastAttempt = ""
            sets[si].sentences[wi].feedback = nil
        }
        sets[si].session += 1
        persist()
    }

    // MARK: - Save from Translator

    func containsSavedTranslation(vietnamese: String, english: String) -> Bool {
        sets.contains { set in
            set.sentences.contains {
                $0.vietnamese == vietnamese && $0.referenceEnglish == english
            }
        }
    }

    /// Toggles a translated sentence into the "Saved from Translator" set.
    @discardableResult
    func toggleSavedTranslation(vietnamese: String, english: String) -> Bool {
        let set = ensureSavedSet()
        guard let si = setIndex(set.id) else { return false }

        if let existing = sets[si].sentences.firstIndex(where: {
            $0.vietnamese == vietnamese && $0.referenceEnglish == english
        }) {
            sets[si].sentences.remove(at: existing)
            persist()
            return false
        } else {
            let sentence = PracticeSentence(vietnamese: vietnamese, referenceEnglish: english)
            sets[si].sentences.insert(sentence, at: 0)
            persist()
            return true
        }
    }

    private func ensureSavedSet() -> PracticeSet {
        if let existing = sets.first(where: { $0.title == savedSetTitle }) { return existing }
        let s = PracticeSet(title: savedSetTitle, sentences: [])
        sets.insert(s, at: 0)
        persist()
        return s
    }

    /// Replaces all practice sets (used when importing a backup) and persists.
    func restore(_ sets: [PracticeSet]) {
        self.sets = sets
        persist()
    }

    // MARK: - Persistence

    private func setIndex(_ id: UUID) -> Int? { sets.firstIndex { $0.id == id } }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PracticeSet].self, from: data) else { return }
        sets = decoded
    }

    private func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey), sets.isEmpty else { return }
        sets = [.sample]
        UserDefaults.standard.set(true, forKey: seededKey)
        persist()
    }
}
