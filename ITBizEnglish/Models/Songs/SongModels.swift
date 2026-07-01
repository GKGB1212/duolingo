//
//  SongModels.swift
//  ITBizEnglish
//
//  Data types for the "Học qua bài hát" (learn-through-songs) feature, kept
//  separate from the vocabulary/deck system:
//   • SongResult — one song from Apple's free, key-less iTunes Search API
//                  (title, artist, artwork, 30s preview URL).
//   • LyricLine  — one line of lyrics; `time` is set when the lyrics are
//                  time-synced (LRC), nil for plain lyrics.
//   • SongLyrics — the full lyrics fetched for a song (from LRCLIB).
//

import Foundation

/// One song returned by the iTunes Search API. Codable so saved songs persist.
struct SongResult: Identifiable, Hashable, Codable {
    let id: Int            // trackId
    let title: String      // trackName
    let artist: String     // artistName
    let album: String?     // collectionName
    let artworkURL: URL?   // upscaled from artworkUrl100
    let previewURL: URL?   // 30-second m4a preview
    let trackViewURL: URL? // Apple Music / iTunes page for this track
    let durationMS: Int?   // trackTimeMillis

    /// Whole-song duration in seconds (for LRCLIB matching), if known.
    var durationSeconds: Int? { durationMS.map { Int(round(Double($0) / 1000)) } }

    /// Opens this track in Apple Music (falls back to an Apple Music search).
    var appleMusicURL: URL? {
        trackViewURL ?? URL(string: "https://music.apple.com/search?term=\(Self.encoded("\(title) \(artist)"))")
    }

    /// Opens the Spotify app (or web) to search results for this song.
    var spotifyURL: URL? {
        URL(string: "https://open.spotify.com/search/\(Self.encoded("\(title) \(artist)"))")
    }

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }
}

/// A word the user saved from a song's lyrics — kept in its own list (separate
/// from the vocabulary decks), so they can review, hear and re-translate it.
struct SavedWord: Identifiable, Codable, Hashable {
    var id = UUID()
    var word: String        // English (cleaned of surrounding punctuation)
    var meaning: String?    // Vietnamese — filled in lazily after saving
    var line: String        // the lyric line it came from (context)
    var songTitle: String
    var songArtist: String
    var dateAdded: Date = .now
}

/// One line of lyrics. `time` is the start offset (seconds) when the lyric is
/// time-synced (LRC); nil for plain, unsynced lyrics.
struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: TimeInterval?
    let text: String
}

// MARK: - Saved snapshot (offline copy of a bookmarked song's lyrics)

/// A persisted lyric line: its text, optional sync time, and the Vietnamese
/// translation captured when the song was saved (nil if that line wasn't
/// translated yet).
struct SavedLyricLine: Codable, Hashable {
    let time: TimeInterval?
    let text: String
    var translation: String?
}

/// A snapshot of a bookmarked song's lyrics + translation, stored so reopening
/// the song shows the saved copy instead of re-hitting the lyrics/translate API.
struct SavedSongLyrics: Codable, Hashable {
    let songID: Int            // SongResult.id (iTunes trackId)
    let isSynced: Bool
    var lines: [SavedLyricLine]

    /// Any non-empty translation present in the snapshot.
    var hasTranslation: Bool {
        lines.contains { !($0.translation ?? "").isEmpty }
    }
}

/// The lyrics fetched for a song.
struct SongLyrics {
    let lines: [LyricLine]
    /// True when the lines carry timestamps (LRC) rather than plain text.
    let isSynced: Bool
    let plainText: String
}

// MARK: - Errors

enum SongServiceError: LocalizedError {
    case badResponse
    case notFound
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:    return "Máy chủ trả về dữ liệu không hợp lệ. Thử lại nhé."
        case .notFound:       return "Chưa tìm thấy lời cho bài này."
        case .network(let r): return r
        }
    }
}

/// A clear Vietnamese reason for a low-level networking failure — shared by the
/// song services so messages stay consistent.
func songNetworkReason(_ error: URLError) -> String {
    switch error.code {
    case .notConnectedToInternet:
        return "Không có kết nối Internet. Kiểm tra mạng (Wi-Fi/4G) rồi thử lại."
    case .timedOut:
        return "Hết thời gian chờ máy chủ — mạng yếu. Thử lại nhé."
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
        return "Không kết nối được tới máy chủ (có thể do mạng / VPN / tường lửa)."
    case .networkConnectionLost:
        return "Mất kết nối giữa chừng. Thử lại nhé."
    default:
        return "Lỗi mạng (mã \(error.code.rawValue)). Kiểm tra mạng và thử lại."
    }
}
