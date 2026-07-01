//
//  DeckStore.swift
//  ITBizEnglish
//
//  Single source of truth for Memrise-style decks. Persists to a JSON file in
//  Application Support (handles larger data better than UserDefaults). Includes
//  the bulk JSON import parser.
//

import Foundation
import Observation

@Observable
final class DeckStore {
    private(set) var decks: [WordDeck] = []

    private let filename = "decks.v1.json"
    private var seededFlagKey = "itbiz.decks.seeded.v1"

    init() {
        load()
        seedIfNeeded()
    }

    // MARK: - Deck CRUD

    func deck(id: UUID) -> WordDeck? { decks.first { $0.id == id } }

    @discardableResult
    func createDeck(title: String) -> WordDeck {
        let deck = WordDeck(title: title.trimmingCharacters(in: .whitespacesAndNewlines), words: [])
        decks.insert(deck, at: 0)
        persist()
        return deck
    }

    func renameDeck(id: UUID, to title: String) {
        guard let i = index(of: id) else { return }
        decks[i].title = title
        persist()
    }

    func setIcon(_ icon: String, forDeck id: UUID) {
        guard let i = index(of: id) else { return }
        decks[i].icon = icon
        persist()
    }

    func setAppearance(icon: String, colorHex: UInt32, forDeck id: UUID) {
        guard let i = index(of: id) else { return }
        decks[i].icon = icon
        decks[i].colorHex = colorHex
        persist()
    }

    func deleteDeck(id: UUID) {
        decks.removeAll { $0.id == id }
        persist()
    }

    func deleteDecks(at offsets: IndexSet) {
        decks.remove(atOffsets: offsets)
        persist()
    }

    // MARK: - Word CRUD

    func addWords(_ words: [DeckWord], toDeck id: UUID) {
        guard let i = index(of: id) else { return }
        decks[i].words.append(contentsOf: words)
        persist()
    }

    /// Persists an updated word back into its deck (used after each answer).
    func update(_ word: DeckWord, inDeck deckID: UUID) {
        guard let di = index(of: deckID),
              let wi = decks[di].words.firstIndex(where: { $0.id == word.id }) else { return }
        decks[di].words[wi] = word
        persist()
    }

    func deleteWord(_ wordID: UUID, fromDeck deckID: UUID) {
        guard let di = index(of: deckID) else { return }
        decks[di].words.removeAll { $0.id == wordID }
        persist()
    }

    /// Flag / unflag a word as difficult.
    func toggleDifficult(_ wordID: UUID, inDeck deckID: UUID) {
        guard let di = index(of: deckID),
              let wi = decks[di].words.firstIndex(where: { $0.id == wordID }) else { return }
        decks[di].words[wi].isDifficult.toggle()
        persist()
    }

    // MARK: - JSON Import

    enum ImportError: LocalizedError {
        case empty
        case invalidJSON
        case noValidWords

        var errorDescription: String? {
            switch self {
            case .empty:        return "Paste some JSON first."
            case .invalidJSON:  return "That isn't valid JSON. Expected an array like [{\"word\": \"...\", \"meaning\": \"...\"}]."
            case .noValidWords: return "No words found. Each item needs at least \"word\" and \"meaning\"."
            }
        }
    }

    /// Shape accepted by the importer. `pronunciation`/`example` are optional.
    private struct ImportRow: Decodable {
        let word: String
        let meaning: String
        let pronunciation: String?
        let example: String?
    }

    /// Parses a bulk JSON string into DeckWords. Throws a friendly error.
    func parseWords(fromJSON json: String) throws -> [DeckWord] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        guard let data = trimmed.data(using: .utf8) else { throw ImportError.invalidJSON }

        let rows: [ImportRow]
        do {
            rows = try JSONDecoder().decode([ImportRow].self, from: data)
        } catch {
            throw ImportError.invalidJSON
        }

        let words = rows.compactMap { row -> DeckWord? in
            let w = row.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let m = row.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, !m.isEmpty else { return nil }
            return DeckWord(
                word: w,
                meaning: m,
                pronunciation: (row.pronunciation ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                example: (row.example ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !words.isEmpty else { throw ImportError.noValidWords }
        return words
    }

    /// Imports words into an existing deck, or creates a new deck if `deckID` is nil.
    @discardableResult
    func importWords(fromJSON json: String,
                     intoDeck deckID: UUID?,
                     newDeckTitle: String) throws -> WordDeck {
        let words = try parseWords(fromJSON: json)
        if let deckID, index(of: deckID) != nil {
            addWords(words, toDeck: deckID)
            return deck(id: deckID)!
        } else {
            let deck = WordDeck(title: newDeckTitle.isEmpty ? "Imported Deck" : newDeckTitle, words: words)
            decks.insert(deck, at: 0)
            persist()
            return deck
        }
    }

    // MARK: - Backup restore

    /// Replaces all decks (used when importing a backup) and persists.
    func restore(_ decks: [WordDeck]) {
        self.decks = decks
        persist()
    }

    // MARK: - Persistence

    private func index(of id: UUID) -> Int? { decks.firstIndex { $0.id == id } }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(decks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("DeckStore persist failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([WordDeck].self, from: data) else { return }
        decks = decoded
    }

    private func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededFlagKey), decks.isEmpty else { return }
        decks = [.sample]
        UserDefaults.standard.set(true, forKey: seededFlagKey)
        persist()
    }
}
