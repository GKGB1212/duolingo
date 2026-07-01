//
//  ITunesSearchService.swift
//  ITBizEnglish
//
//  Song search powered by Apple's free, public iTunes Search API — no API key
//  required. Returns a list of songs with artwork + a 30-second preview URL so
//  the user can sample a track before opening its lyrics.
//
//  Endpoint: https://itunes.apple.com/search?term=…&media=music&entity=song
//  (rate-limited to ~20 calls/minute, so we search on submit, not per keystroke.)
//

import Foundation

enum ITunesSearchService {

    /// Searches for songs matching `term`. Returns [] for an empty query.
    static func search(_ term: String, limit: Int = 25) async throws -> [SongResult] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: q),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = comps.url else { throw SongServiceError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw SongServiceError.badResponse
            }
            let payload = try JSONDecoder().decode(ITunesResponse.self, from: data)
            // De-duplicate by trackId (the API can repeat the same song).
            var seen = Set<Int>()
            return payload.results.compactMap { $0.asSong }.filter { seen.insert($0.id).inserted }
        } catch let error as SongServiceError {
            throw error
        } catch let error as URLError {
            throw SongServiceError.network(songNetworkReason(error))
        } catch {
            throw SongServiceError.badResponse
        }
    }
}

// MARK: - Wire models

private struct ITunesResponse: Decodable {
    let results: [Item]

    struct Item: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let previewUrl: String?
        let trackViewUrl: String?
        let trackTimeMillis: Int?

        /// Maps the raw item to our model; drops rows missing the essentials.
        var asSong: SongResult? {
            guard let id = trackId, let title = trackName, let artist = artistName else { return nil }
            // Ask for a crisper 300×300 cover instead of the default 100×100.
            let art = artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "300x300bb")
            return SongResult(
                id: id,
                title: title,
                artist: artist,
                album: collectionName,
                artworkURL: art.flatMap { URL(string: $0) },
                previewURL: previewUrl.flatMap { URL(string: $0) },
                trackViewURL: trackViewUrl.flatMap { URL(string: $0) },
                durationMS: trackTimeMillis
            )
        }
    }
}
