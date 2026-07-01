//
//  SongLibraryView.swift
//  ITBizEnglish
//
//  The "Đã lưu" screen of the Bài hát tab: bookmarked songs and the words saved
//  from lyrics. Kept separate from the vocabulary decks. Tap a saved song to see
//  the words you saved from it (and from there open its full lyrics); tap a
//  word's speaker to hear it.
//

import SwiftUI

struct SongLibraryView: View {
    @State private var library = SongLibraryStore.shared
    @State private var speech = SpeechSynthesizer()

    var body: some View {
        ZStack {
            AppBackground()
            if library.savedSongs.isEmpty && library.savedWords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        if !library.savedSongs.isEmpty { songsSection }
                        let others = orphanWords
                        if !others.isEmpty { otherWordsSection(others) }
                    }
                    .padding(Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .navigationTitle("Đã lưu")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speech.stop() }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bookmark").font(.system(size: 46)).foregroundStyle(.brand)
            Text("Chưa lưu gì cả").font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Lưu bài hát bằng nút đánh dấu, và chạm từ trong lời bài hát để lưu lại học sau.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Songs

    private var songsSection: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("BÀI HÁT ĐÃ LƯU").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            ForEach(library.savedSongs) { song in
                let count = wordCount(for: song)
                NavigationLink(value: SongRoute.savedWords(song)) {
                    SongCardRow(song: song, artworkSize: 50,
                                badge: count > 0 ? "\(count) từ" : nil)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation { library.removeSong(song) }
                    } label: { Label("Bỏ lưu", systemImage: "bookmark.slash") }
                }
            }
        }
    }

    // MARK: - Words from songs that aren't bookmarked

    /// Words saved from songs the user didn't (or no longer) bookmark — shown here
    /// so they stay reachable (a song's own words live inside that song's screen).
    private func otherWordsSection(_ words: [SavedWord]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TỪ KHÁC ĐÃ LƯU (\(words.count))")
                .font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    SavedWordRow(word: word, speech: speech) {
                        withAnimation { library.removeWord(word) }
                    }
                    if index < words.count - 1 {
                        Divider().overlay(Color.duoSwan).padding(.leading, 52)
                    }
                }
            }
            .duoCard(cornerRadius: Theme.Radius.card)
        }
    }

    // MARK: - Helpers

    private func wordCount(for song: SongResult) -> Int {
        library.savedWords.reduce(0) { $0 + (SongWords.matches($1, song) ? 1 : 0) }
    }

    private var orphanWords: [SavedWord] {
        let keys = Set(library.savedSongs.map(SongWords.key(for:)))
        return library.savedWords.filter { !keys.contains(SongWords.key(for: $0)) }
    }
}

// MARK: - Matching words to their source song

/// Helpers to relate saved words to songs (by title + artist).
enum SongWords {
    static func matches(_ word: SavedWord, _ song: SongResult) -> Bool {
        word.songTitle == song.title && word.songArtist == song.artist
    }

    static func key(for song: SongResult) -> String { "\(song.title)\u{1}\(song.artist)" }
    static func key(for word: SavedWord) -> String { "\(word.songTitle)\u{1}\(word.songArtist)" }
}

// MARK: - A song's saved words

/// Shows the words saved from one song, plus a shortcut back into its full
/// lyrics. Reached by tapping a song in the saved library.
struct SongSavedWordsView: View {
    let song: SongResult

    @State private var library = SongLibraryStore.shared
    @State private var speech = SpeechSynthesizer()

    private var words: [SavedWord] {
        library.savedWords.filter { SongWords.matches($0, song) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    if words.isEmpty { emptyWords } else { wordsCard }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .navigationTitle("Từ đã lưu")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speech.stop() }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                SongArtwork(url: song.artworkURL, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(2)
                    Text(song.artist).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // Reuses the lyrics destination already registered on this stack.
            NavigationLink(value: SongRoute.lyrics(song)) {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft").font(.footnote.weight(.bold))
                    Text("Mở lời bài hát").font(.subheadline.weight(.heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.brand))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var emptyWords: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "bookmark").font(.system(size: 40)).foregroundStyle(.brand)
            Text("Chưa lưu từ nào từ bài này").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Mở lời bài hát rồi chạm vào từng từ để lưu lại học sau.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TỪ ĐÃ LƯU (\(words.count))")
                .font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    SavedWordRow(word: word, speech: speech, showSongTitle: false) {
                        withAnimation { library.removeWord(word) }
                    }
                    if index < words.count - 1 {
                        Divider().overlay(Color.duoSwan).padding(.leading, 52)
                    }
                }
            }
            .duoCard(cornerRadius: Theme.Radius.card)
        }
    }
}

// MARK: - Shared saved-word row

/// One saved-word row (speaker • word + meaning + optional source • delete),
/// reused by the library's "other words" list and a song's saved-words screen.
struct SavedWordRow: View {
    let word: SavedWord
    var speech: SpeechSynthesizer
    var showSongTitle: Bool = true
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { speech.speak(word.word, id: word.id.uuidString) } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(speech.speakingID == word.id.uuidString ? Color.brand : .duoBlue)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(word.word).font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                if let meaning = word.meaning, !meaning.isEmpty {
                    Text(meaning).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf).lineLimit(2)
                }
                if showSongTitle {
                    Text("🎵 \(word.songTitle)").font(.caption.weight(.semibold)).foregroundStyle(.duoHare).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { onDelete() } label: {
                Image(systemName: "trash").font(.subheadline).foregroundStyle(.duoRed)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12).padding(.horizontal, Theme.Spacing.md)
    }
}

#Preview {
    NavigationStack { SongLibraryView() }
}
