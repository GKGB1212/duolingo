//
//  BackupService.swift
//  ITBizEnglish
//
//  Manual cross-device sync: bundle every store's data into one JSON backup
//  file the user can share (AirDrop / Files / iCloud Drive) and import on
//  another device. No account or server — the file IS the transport.
//
//  Covers decks, self-translate sets, chat history, flashcards + translation
//  history, saved songs + words, and API keys (so AI works on the other
//  device). Device-specific settings (theme, voice) are intentionally left out.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Backup payload

/// One self-contained snapshot of everything worth syncing. Every section has a
/// custom-decoded default so a backup from a different app version (missing or
/// extra sections) still restores what it can instead of failing outright.
struct BackupData: Codable {
    var format = BackupData.expectedFormat
    var version = 1
    var exportedAt = Date()

    var decks: [WordDeck] = []
    var practiceSets: [PracticeSet] = []
    var chatHistory: [ChatHistoryEntry] = []
    var flashcards: [Flashcard] = []
    var translationHistory: [TranslationResult] = []
    var savedSongs: [SongResult] = []
    var savedWords: [SavedWord] = []
    var grammarLessons: [SavedGrammarLesson] = []
    var grammarMistakes: [GrammarMistakeEntry] = []
    var credentials: [APICredential] = []

    static let expectedFormat = "itbiz.backup"

    init() {}

    init(decks: [WordDeck], practiceSets: [PracticeSet], chatHistory: [ChatHistoryEntry],
         flashcards: [Flashcard], translationHistory: [TranslationResult],
         savedSongs: [SongResult], savedWords: [SavedWord],
         grammarLessons: [SavedGrammarLesson], grammarMistakes: [GrammarMistakeEntry],
         credentials: [APICredential]) {
        self.decks = decks
        self.practiceSets = practiceSets
        self.chatHistory = chatHistory
        self.flashcards = flashcards
        self.translationHistory = translationHistory
        self.savedSongs = savedSongs
        self.savedWords = savedWords
        self.grammarLessons = grammarLessons
        self.grammarMistakes = grammarMistakes
        self.credentials = credentials
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        decks = try c.decodeIfPresent([WordDeck].self, forKey: .decks) ?? []
        practiceSets = try c.decodeIfPresent([PracticeSet].self, forKey: .practiceSets) ?? []
        chatHistory = try c.decodeIfPresent([ChatHistoryEntry].self, forKey: .chatHistory) ?? []
        flashcards = try c.decodeIfPresent([Flashcard].self, forKey: .flashcards) ?? []
        translationHistory = try c.decodeIfPresent([TranslationResult].self, forKey: .translationHistory) ?? []
        savedSongs = try c.decodeIfPresent([SongResult].self, forKey: .savedSongs) ?? []
        savedWords = try c.decodeIfPresent([SavedWord].self, forKey: .savedWords) ?? []
        grammarLessons = try c.decodeIfPresent([SavedGrammarLesson].self, forKey: .grammarLessons) ?? []
        grammarMistakes = try c.decodeIfPresent([GrammarMistakeEntry].self, forKey: .grammarMistakes) ?? []
        credentials = try c.decodeIfPresent([APICredential].self, forKey: .credentials) ?? []
    }

    /// Short human summary of what's inside (for the import confirmation).
    var summary: String {
        var parts: [String] = []
        if !decks.isEmpty { parts.append("\(decks.count) bộ từ") }
        if !practiceSets.isEmpty { parts.append("\(practiceSets.count) bộ câu") }
        if !chatHistory.isEmpty { parts.append("\(chatHistory.count) phiên chat") }
        if !flashcards.isEmpty { parts.append("\(flashcards.count) thẻ dịch") }
        if !savedSongs.isEmpty { parts.append("\(savedSongs.count) bài hát") }
        if !grammarLessons.isEmpty { parts.append("\(grammarLessons.count) bài ngữ pháp") }
        if !grammarMistakes.isEmpty { parts.append("\(grammarMistakes.count) lỗi ngữ pháp") }
        if !credentials.isEmpty { parts.append("\(credentials.count) API key") }
        return parts.isEmpty ? "trống" : parts.joined(separator: " · ")
    }
}

enum BackupError: LocalizedError {
    case invalidFile
    case readFailed

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "File không phải bản sao lưu của ITBizEnglish."
        case .readFailed:  return "Không đọc được file đã chọn."
        }
    }
}

// MARK: - Service

enum BackupService {

    /// Encodes a snapshot of all stores into pretty-printed JSON.
    static func makeData(decks: DeckStore, practice: PracticeStore, chat: ChatHistoryStore,
                         flashcards: FlashcardStore, songs: SongLibraryStore,
                         grammar: GrammarStore, grammarMistakes: GrammarMistakeStore,
                         settings: AppSettings) throws -> Data {
        let backup = BackupData(
            decks: decks.decks,
            practiceSets: practice.sets,
            chatHistory: chat.entries,
            flashcards: flashcards.flashcards,
            translationHistory: flashcards.history,
            savedSongs: songs.savedSongs,
            savedWords: songs.savedWords,
            grammarLessons: grammar.lessons,
            grammarMistakes: grammarMistakes.entries,
            credentials: settings.credentials
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// A timestamped filename for the exported backup.
    static func suggestedFilename(date: Date = .now) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "ITBizEnglish-backup-\(f.string(from: date)).json"
    }

    /// Writes the backup to a temp file and returns its URL (for the share sheet).
    static func writeTempFile(decks: DeckStore, practice: PracticeStore, chat: ChatHistoryStore,
                              flashcards: FlashcardStore, songs: SongLibraryStore,
                              grammar: GrammarStore, grammarMistakes: GrammarMistakeStore,
                              settings: AppSettings) throws -> URL {
        let data = try makeData(decks: decks, practice: practice, chat: chat,
                                flashcards: flashcards, songs: songs, grammar: grammar,
                                grammarMistakes: grammarMistakes, settings: settings)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename())
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Decodes and applies a backup file to every store. Replaces existing data.
    @discardableResult
    static func restore(from url: URL, decks: DeckStore, practice: PracticeStore,
                        chat: ChatHistoryStore, flashcards: FlashcardStore,
                        songs: SongLibraryStore, grammar: GrammarStore,
                        grammarMistakes: GrammarMistakeStore,
                        settings: AppSettings) throws -> BackupData {
        // Security-scoped access is needed for files picked from other apps (Files, iCloud).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw BackupError.readFailed }
        return try restore(data: data, decks: decks, practice: practice, chat: chat,
                           flashcards: flashcards, songs: songs, grammar: grammar,
                           grammarMistakes: grammarMistakes, settings: settings)
    }

    /// Decodes and applies a backup payload (file or cloud) to every store.
    @discardableResult
    static func restore(data: Data, decks: DeckStore, practice: PracticeStore,
                        chat: ChatHistoryStore, flashcards: FlashcardStore,
                        songs: SongLibraryStore, grammar: GrammarStore,
                        grammarMistakes: GrammarMistakeStore,
                        settings: AppSettings) throws -> BackupData {
        let backup = try JSONDecoder().decode(BackupData.self, from: data)
        guard backup.format == BackupData.expectedFormat else { throw BackupError.invalidFile }

        decks.restore(backup.decks)
        practice.restore(backup.practiceSets)
        chat.restore(backup.chatHistory)
        flashcards.restore(flashcards: backup.flashcards, history: backup.translationHistory)
        songs.restore(songs: backup.savedSongs, words: backup.savedWords)
        grammar.restore(backup.grammarLessons)
        grammarMistakes.restore(backup.grammarMistakes)
        settings.restore(credentials: backup.credentials)
        return backup
    }
}

// MARK: - Share sheet wrapper

/// Minimal UIActivityViewController bridge so SwiftUI can present the iOS share
/// sheet (AirDrop, Save to Files, Messages…) for the exported backup file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
