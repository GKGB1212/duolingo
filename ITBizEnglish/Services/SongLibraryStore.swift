//
//  SongLibraryStore.swift
//  ITBizEnglish
//
//  Local persistence for the "Bài hát" feature, kept separate from the
//  vocabulary decks (the user's choice): the songs the user bookmarked and the
//  individual words they saved from lyrics. Backed by UserDefaults (JSON), in
//  the same lightweight style as the app's other stores. Shared singleton so
//  the search, lyrics and library screens all stay in sync.
//

import Foundation
import Observation

@Observable
final class SongLibraryStore {
    static let shared = SongLibraryStore()

    private(set) var savedSongs: [SongResult] = []
    private(set) var savedWords: [SavedWord] = []
    /// Offline lyric+translation snapshots for bookmarked songs (keyed by songID).
    @ObservationIgnored private(set) var savedLyrics: [SavedSongLyrics] = []

    @ObservationIgnored private static let songsKey = "itbiz.songs.saved.v1"
    @ObservationIgnored private static let wordsKey = "itbiz.songWords.saved.v1"
    @ObservationIgnored private static let lyricsKey = "itbiz.songLyrics.saved.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.songsKey),
           let decoded = try? JSONDecoder().decode([SongResult].self, from: data) {
            savedSongs = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.wordsKey),
           let decoded = try? JSONDecoder().decode([SavedWord].self, from: data) {
            savedWords = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.lyricsKey),
           let decoded = try? JSONDecoder().decode([SavedSongLyrics].self, from: data) {
            savedLyrics = decoded
        }
    }

    // MARK: - Songs

    func isSongSaved(_ song: SongResult) -> Bool {
        savedSongs.contains { $0.id == song.id }
    }

    /// Bookmarks the song if new, removes it if already saved. Returns the new state.
    @discardableResult
    func toggleSong(_ song: SongResult) -> Bool {
        if let index = savedSongs.firstIndex(where: { $0.id == song.id }) {
            savedSongs.remove(at: index)
            persistSongs()
            return false
        }
        savedSongs.insert(song, at: 0)
        persistSongs()
        return true
    }

    /// Bookmarks a song together with an offline snapshot of its lyrics +
    /// translation (so reopening it skips the API). Pass `nil` lyrics to save
    /// just the song (e.g. when its lyrics hadn't loaded yet).
    func saveSong(_ song: SongResult, lyrics: SavedSongLyrics?) {
        if !savedSongs.contains(where: { $0.id == song.id }) {
            savedSongs.insert(song, at: 0)
            persistSongs()
        }
        if let lyrics { upsertLyrics(lyrics) }
    }

    /// The saved offline snapshot for a song, if one exists.
    func lyricsSnapshot(forSongID id: Int) -> SavedSongLyrics? {
        savedLyrics.first { $0.songID == id }
    }

    /// Stores or refreshes the offline lyric snapshot for a song.
    func upsertLyrics(_ lyrics: SavedSongLyrics) {
        if let i = savedLyrics.firstIndex(where: { $0.songID == lyrics.songID }) {
            savedLyrics[i] = lyrics
        } else {
            savedLyrics.append(lyrics)
        }
        persistLyrics()
    }

    func removeSong(_ song: SongResult) {
        savedSongs.removeAll { $0.id == song.id }
        savedLyrics.removeAll { $0.songID == song.id }
        persistSongs()
        persistLyrics()
    }

    func removeSongs(at offsets: IndexSet) {
        let removedIDs = offsets.map { savedSongs[$0].id }
        savedSongs.remove(atOffsets: offsets)
        savedLyrics.removeAll { removedIDs.contains($0.songID) }
        persistLyrics()
        persistSongs()
    }

    // MARK: - Words

    func isWordSaved(_ word: String, songTitle: String) -> Bool {
        let w = word.lowercased()
        return savedWords.contains { $0.word.lowercased() == w && $0.songTitle == songTitle }
    }

    /// Saves the word if new, removes it if already saved (toggle, scoped to the
    /// song). Returns the id when it was just saved (so the caller can fill in the
    /// meaning), or nil when it was removed.
    @discardableResult
    func toggleWord(_ word: String, line: String, song: SongResult, meaning: String?) -> UUID? {
        let w = word.lowercased()
        if let index = savedWords.firstIndex(where: { $0.word.lowercased() == w && $0.songTitle == song.title }) {
            savedWords.remove(at: index)
            persistWords()
            return nil
        }
        let saved = SavedWord(word: word, meaning: meaning, line: line,
                              songTitle: song.title, songArtist: song.artist)
        savedWords.insert(saved, at: 0)
        persistWords()
        return saved.id
    }

    func setMeaning(_ meaning: String, forWord id: UUID) {
        guard let index = savedWords.firstIndex(where: { $0.id == id }) else { return }
        savedWords[index].meaning = meaning
        persistWords()
    }

    func removeWord(_ word: SavedWord) {
        savedWords.removeAll { $0.id == word.id }
        persistWords()
    }

    func removeWords(at offsets: IndexSet) {
        savedWords.remove(atOffsets: offsets)
        persistWords()
    }

    /// Replaces saved songs + words (used when importing a backup) and persists.
    func restore(songs: [SongResult], words: [SavedWord]) {
        self.savedSongs = songs
        self.savedWords = words
        persistSongs()
        persistWords()
    }

    // MARK: - Persistence

    private func persistSongs() {
        if let data = try? JSONEncoder().encode(savedSongs) {
            UserDefaults.standard.set(data, forKey: Self.songsKey)
        }
    }

    private func persistWords() {
        if let data = try? JSONEncoder().encode(savedWords) {
            UserDefaults.standard.set(data, forKey: Self.wordsKey)
        }
    }

    private func persistLyrics() {
        if let data = try? JSONEncoder().encode(savedLyrics) {
            UserDefaults.standard.set(data, forKey: Self.lyricsKey)
        }
    }
}
