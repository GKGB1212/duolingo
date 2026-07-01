//
//  LyricsService.swift
//  ITBizEnglish
//
//  Fetches the full lyrics of a chosen song from LRCLIB — a free, key-less,
//  community lyrics database (https://lrclib.net). Prefers time-synced (LRC)
//  lyrics and falls back to plain lyrics. Also exposes LineTranslator, which
//  reuses the app's LLMClient to translate a single lyric line into Vietnamese.
//
//  Strategy: try the exact /api/get (artist + track + album + duration); if
//  that misses, fall back to the more lenient /api/search.
//

import Foundation

enum LyricsService {

    private static let userAgent = "ITBizEnglish iOS (English learning app)"

    /// Fetches the best available lyrics for `song`, full song (not just the
    /// preview window). Throws `.notFound` when no lyrics exist anywhere.
    static func fetch(for song: SongResult) async throws -> SongLyrics {
        if let exact = try await getExact(song) { return exact }
        if let found = try await searchBest(track: song.title, artist: song.artist) { return found }
        // Last resort: a looser free-text search.
        if let loose = try await searchBest(query: "\(song.title) \(song.artist)") { return loose }
        throw SongServiceError.notFound
    }

    // MARK: - LRCLIB endpoints

    /// `/api/get` — exact lookup; returns nil (so the caller falls back) on any
    /// miss instead of throwing.
    private static func getExact(_ song: SongResult) async throws -> SongLyrics? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "artist_name", value: song.artist),
            URLQueryItem(name: "track_name", value: song.title)
        ]
        if let album = song.album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let dur = song.durationSeconds { items.append(URLQueryItem(name: "duration", value: String(dur))) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }

        guard let data = try await fetchData(url) else { return nil }
        guard let track = try? JSONDecoder().decode(LRCLibTrack.self, from: data) else { return nil }
        return lyrics(from: track)
    }

    /// `/api/search` with structured track/artist names.
    private static func searchBest(track: String, artist: String) async throws -> SongLyrics? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        return try await searchBest(comps: comps)
    }

    /// `/api/search` with a single free-text query.
    private static func searchBest(query: String) async throws -> SongLyrics? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        return try await searchBest(comps: comps)
    }

    private static func searchBest(comps: URLComponents) async throws -> SongLyrics? {
        guard let url = comps.url, let data = try await fetchData(url) else { return nil }
        guard let tracks = try? JSONDecoder().decode([LRCLibTrack].self, from: data) else { return nil }
        // Prefer a result that has synced lyrics, else the first with any lyrics.
        let best = tracks.first { ($0.syncedLyrics?.isEmpty == false) }
                 ?? tracks.first { ($0.plainLyrics?.isEmpty == false) }
        return best.flatMap(lyrics(from:))
    }

    /// Shared GET that returns the body for 2xx, nil for 404 (a clean miss), and
    /// throws a friendly error for real network failures.
    private static func fetchData(_ url: URL) async throws -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch let error as URLError {
            throw SongServiceError.network(songNetworkReason(error))
        }
    }

    // MARK: - Building SongLyrics

    private static func lyrics(from track: LRCLibTrack) -> SongLyrics? {
        if let synced = track.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                let plain = track.plainLyrics ?? lines.map(\.text).joined(separator: "\n")
                return SongLyrics(lines: lines, isSynced: true, plainText: plain)
            }
        }
        if let plain = track.plainLyrics,
           !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain.components(separatedBy: .newlines).map { LyricLine(time: nil, text: $0) }
            return SongLyrics(lines: lines, isSynced: false, plainText: plain)
        }
        return nil
    }

    /// Parses an LRC string into time-ordered lines. Handles multiple timestamps
    /// per line and ignores metadata tags like `[ar:…]` / `[ti:…]`.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var out: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }   // skip metadata-only lines

            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)

            for m in matches {
                let minutes = Int(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Int(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    fraction = Double("0." + ns.substring(with: m.range(at: 3))) ?? 0
                }
                let time = TimeInterval(minutes * 60 + seconds) + fraction
                out.append(LyricLine(time: time, text: text))
            }
        }
        return out.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }
}

// MARK: - Single-line translation (reuses the app's LLM client)

enum LineTranslator {
    /// Translates one English lyric line into natural Vietnamese.
    static func translate(_ english: String) async throws -> String {
        let line = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return "" }

        let system = """
        You translate a single line of an English song lyric into Vietnamese that \
        feels ALIVE — capturing its emotion, tone and any irony, sarcasm or \
        hidden meaning, never a stiff word-for-word rendering. If the line is \
        sarcastic, mocking or suggestive, keep that edge; turn idioms and \
        metaphors into natural Vietnamese (an equivalent image, not the literal \
        words). Stay faithful even if it is mature or 18+; do not censor or \
        soften. Respond with raw JSON only, no markdown, no extra text, in \
        exactly this shape: {"vi": "string"}.
        """
        let content = try await LLMClient.generateJSON(system: system, user: line, temperature: 0.78)
        guard let data = content.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data),
              let vi = object["vi"], !vi.isEmpty else {
            throw SongServiceError.badResponse
        }
        return vi
    }
}

// MARK: - Whole-song translation (one LLM call for all lines)

enum LyricsTranslator {
    /// Translates every line in one call. Returns Vietnamese aligned 1:1 with the
    /// input (empty input lines map to empty strings). Throws on a count mismatch.
    static func translateAll(_ lines: [String]) async throws -> [String] {
        guard !lines.isEmpty else { return [] }

        let payload = try JSONEncoder().encode(lines)
        let user = String(data: payload, encoding: .utf8) ?? "[]"
        let system = """
        You are a master Vietnamese translator of song lyrics — part poet, part \
        storyteller. The user message is a JSON array of the lines of ONE song, \
        in order (some lines may be empty).

        STEP 1 — Read the ENTIRE song first and truly understand:
        • the story and the emotional arc — where it builds, breaks, resolves;
        • the narrator's voice and attitude — tender, heartbroken, cocky, \
          playful, bitter, sensual…;
        • the SUBTEXT — irony, sarcasm, double meanings, metaphors, wordplay, \
          slang and cultural references.

        STEP 2 — Translate into Vietnamese that:
        • conveys the MEANING and FEELING, NEVER word-for-word — a Vietnamese \
          listener should feel exactly what an English listener feels;
        • keeps irony ironic and sarcasm biting — do NOT flatten a sarcastic, \
          mocking or suggestive line into a plain literal one; render the hidden \
          intent so it still stings, winks or seduces;
        • turns idioms and metaphors into Vietnamese that lands naturally — find \
          an equivalent image, don't translate the words;
        • flows as ONE connected piece: keep xưng hô (the I/you pronouns), tense, \
          imagery and tone consistent from the first line to the last;
        • sounds like modern, musical Vietnamese in the song's own register — \
          colloquial / street for rap & pop, poetic for ballads;
        • stays fully FAITHFUL even when the song is mature, explicit, angry, \
          sexual or 18+ — never censor, soften or sanitize.

        Keep the line structure: output EXACTLY one Vietnamese line per input \
        line, same order, same count; an empty input line stays an empty string. \
        Respond with raw JSON only, no markdown, in exactly this shape: \
        {"lines": [ ... ]}.
        """
        let content = try await LLMClient.generateJSON(system: system, user: user, temperature: 0.9)
        guard let data = content.data(using: .utf8),
              let object = try? JSONDecoder().decode(LinesPayload.self, from: data),
              object.lines.count == lines.count else {
            throw SongServiceError.badResponse
        }
        return object.lines
    }

    private struct LinesPayload: Decodable { let lines: [String] }
}

// MARK: - Single-word gloss (when saving a word)

enum WordTranslator {
    /// A short Vietnamese meaning of `word` as used in `context` (its lyric line).
    static func translate(_ word: String, context: String) async throws -> String {
        let system = """
        Give a short Vietnamese meaning of the English word as used in the given \
        lyric line. Respond with raw JSON only: {"vi": "short meaning"}. Keep it \
        concise (a few words), no extra text.
        """
        let user = "word: \(word)\nline: \(context)"
        let content = try await LLMClient.generateJSON(system: system, user: user, temperature: 0.2)
        guard let data = content.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data),
              let vi = object["vi"], !vi.isEmpty else {
            throw SongServiceError.badResponse
        }
        return vi
    }
}

// MARK: - Wire model

private struct LRCLibTrack: Decodable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let plainLyrics: String?
    let syncedLyrics: String?
    let instrumental: Bool?
}
