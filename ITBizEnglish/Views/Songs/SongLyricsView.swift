//
//  SongLyricsView.swift
//  ITBizEnglish
//
//  Full lyrics for a chosen song (from LRCLIB). From here the user can:
//   • replay the 30-second preview,
//   • open the song in Apple Music or Spotify,
//   • bookmark the song,
//   • show/hide the Vietnamese translation of the whole song (under each line),
//   • tap a line to hear it (TTS) and translate just that line,
//   • tap individual words in the selected line to save them for later.
//

import SwiftUI

struct SongLyricsView: View {
    let song: SongResult

    @State private var loadState: LoadState = .loading
    @State private var lyrics: SongLyrics?

    @State private var player = SongPreviewPlayer()
    @State private var speech = SpeechSynthesizer()
    @State private var library = SongLibraryStore.shared
    @Environment(\.openURL) private var openURL

    // Translation state.
    @State private var showTranslation = false
    @State private var translations: [UUID: String] = [:]
    @State private var translatingLineID: UUID?
    @State private var translatingAll = false
    @State private var translateAllFailed = false

    // The line whose word-chips (for saving words) are shown.
    @State private var selectedID: UUID?

    private enum LoadState {
        case loading
        case ready
        case failed(String)
    }

    private var hasAPIKey: Bool { AppSettings.shared.hasCredential }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    switch loadState {
                    case .loading:         loadingBlock
                    case .failed(let msg): failureBlock(msg)
                    case .ready:           if let lyrics { lyricsBlock(lyrics) }
                    }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarButtons }
        .task { await load() }
        .onDisappear { player.stop(); speech.stop() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { toggleTranslation() }
            } label: {
                Image(systemName: showTranslation ? "character.book.closed.fill" : "character.book.closed")
                    .foregroundStyle(showTranslation ? Color.brand : .duoWolf)
            }
            .accessibilityLabel(showTranslation ? "Ẩn bản dịch" : "Hiện bản dịch")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { toggleSave() }
            } label: {
                Image(systemName: library.isSongSaved(song) ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(library.isSongSaved(song) ? Color.brand : .duoWolf)
            }
            .accessibilityLabel(library.isSongSaved(song) ? "Bỏ lưu bài hát" : "Lưu bài hát")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                SongArtwork(url: song.artworkURL, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(2)
                    Text(song.artist).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf).lineLimit(1)
                }
                Spacer(minLength: 0)
                if song.previewURL != nil {
                    Button {
                        Haptics.tap()
                        player.toggle(song)
                    } label: {
                        Image(systemName: player.playingID == song.id ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            streamingButtons
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var streamingButtons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            streamingButton("Apple Music", icon: "music.note", color: .duoRed) {
                if let url = song.appleMusicURL { openURL(url) }
            }
            streamingButton("Spotify", icon: "music.note.list", color: .duoGreen) {
                if let url = song.spotifyURL { openURL(url) }
            }
        }
    }

    private func streamingButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.footnote.weight(.bold))
                Text(title).font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Phase blocks

    private var loadingBlock: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("Đang tải lời bài hát…").font(.callout.weight(.bold)).foregroundStyle(.duoWolf)
        }
        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.lg)
    }

    private func failureBlock(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "text.badge.xmark").font(.largeTitle).foregroundStyle(.duoWolf)
            Text(message)
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
            Button("Thử lại") { Task { await load() } }
                .buttonStyle(.duoBlue).frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity).padding(.top, Theme.Spacing.lg)
    }

    private func lyricsBlock(_ lyrics: SongLyrics) -> some View {
        // Lazy so long songs (50+ lines) only build the rows on screen.
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Chạm vào một dòng để nghe, dịch và chọn từ lưu lại",
                  systemImage: "hand.tap.fill")
                .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                .padding(.bottom, 2)

            if translatingAll {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Đang dịch cả bài…").font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                }
                .padding(.bottom, 2)
            }
            if translateAllFailed {
                Text("Không dịch được cả bài (kiểm tra mạng / API key). Bạn vẫn có thể chạm từng dòng để dịch.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoRed)
            }
            if !hasAPIKey {
                Text("Mẹo: thêm API key trong Cài đặt để dịch lời và lưu nghĩa của từ.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
            }

            ForEach(lyrics.lines) { line in
                lineRow(line)
            }
        }
    }

    // MARK: - Line row

    @ViewBuilder
    private func lineRow(_ line: LyricLine) -> some View {
        let isBlank = line.text.trimmingCharacters(in: .whitespaces).isEmpty
        let isSelected = selectedID == line.id
        let showVI = showTranslation || isSelected

        Button {
            onTap(line)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(isBlank ? "♪" : line.text)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isSelected ? Color.brand : .duoInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    if speech.speakingID == line.id.uuidString {
                        Image(systemName: "speaker.wave.2.fill").font(.footnote).foregroundStyle(.brand)
                    }
                }

                if !isBlank, showVI { translationView(line) }
                if !isBlank, isSelected { wordChips(line) }
            }
            .padding(.vertical, 8).padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.brand.opacity(0.10) : .clear))
        }
        .buttonStyle(.plain)
        .disabled(isBlank)
    }

    @ViewBuilder
    private func translationView(_ line: LyricLine) -> some View {
        if let vi = translations[line.id] {
            Text(vi).font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if translatingLineID == line.id {
            HStack(spacing: 6) {
                ProgressView()
                Text("Đang dịch…").font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
            }
        } else if !hasAPIKey {
            Text("Thêm API key trong Cài đặt để dịch.")
                .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
        }
    }

    /// Tappable word chips for the selected line — tap to save / unsave a word.
    private func wordChips(_ line: LyricLine) -> some View {
        let tokens = line.text.split(separator: " ").map(String.init)
        return VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.duoSwan)
            Label("Chạm từ để lưu", systemImage: "bookmark")
                .font(.caption2.weight(.bold)).foregroundStyle(.duoWolf)
            FlowLayout(spacing: 6) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    wordChip(token, line: line)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func wordChip(_ token: String, line: LyricLine) -> some View {
        let clean = cleanedWord(token)
        if clean.isEmpty {
            Text(token).font(.subheadline.weight(.semibold)).foregroundStyle(.duoWolf)
        } else {
            let saved = library.isWordSaved(clean, songTitle: song.title)
            Button {
                Haptics.tap()
                toggleWord(clean, line: line.text)
            } label: {
                HStack(spacing: 4) {
                    if saved { Image(systemName: "checkmark").font(.caption2.weight(.black)) }
                    Text(token)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(saved ? .white : .duoInk)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(saved ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.duoPolar)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(saved ? Color.brand : Color.duoSwan, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Saving (with offline lyrics + translation snapshot)

    private func toggleSave() {
        if library.isSongSaved(song) {
            library.removeSong(song)          // also drops the offline snapshot
        } else {
            library.saveSong(song, lyrics: currentSnapshot())
        }
    }

    /// Builds a persistable snapshot of the loaded lyrics + current translations.
    /// nil when lyrics haven't loaded yet (then only the song metadata is saved).
    private func currentSnapshot() -> SavedSongLyrics? {
        guard let lyrics else { return nil }
        let lines = lyrics.lines.map { line in
            SavedLyricLine(time: line.time, text: line.text, translation: translations[line.id])
        }
        return SavedSongLyrics(songID: song.id, isSynced: lyrics.isSynced, lines: lines)
    }

    /// Rebuilds the in-memory lyrics + translation map from a saved snapshot.
    /// LyricLine ids are regenerated, so the translation map is rekeyed to match.
    private func restoreLyrics(from snap: SavedSongLyrics) -> (SongLyrics, [UUID: String]) {
        var trans: [UUID: String] = [:]
        let lines = snap.lines.map { saved -> LyricLine in
            let line = LyricLine(time: saved.time, text: saved.text)
            if let t = saved.translation, !t.isEmpty { trans[line.id] = t }
            return line
        }
        let plain = lines.map(\.text).joined(separator: "\n")
        return (SongLyrics(lines: lines, isSynced: snap.isSynced, plainText: plain), trans)
    }

    /// If this song is already bookmarked, refresh its saved snapshot so newly
    /// added translations are kept for next time.
    private func refreshSnapshotIfSaved() {
        guard library.isSongSaved(song), let snap = currentSnapshot() else { return }
        library.upsertLyrics(snap)
    }

    // MARK: - Actions

    private func onTap(_ line: LyricLine) {
        guard !line.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.snappy) { selectedID = line.id }
        speech.speak(line.text, id: line.id.uuidString)

        guard hasAPIKey, translations[line.id] == nil, translatingLineID != line.id else { return }
        translateLine(line)
    }

    private func translateLine(_ line: LyricLine) {
        translatingLineID = line.id
        Task {
            do {
                let vi = try await LineTranslator.translate(line.text)
                await MainActor.run {
                    translations[line.id] = vi
                    translatingLineID = nil
                    refreshSnapshotIfSaved()
                }
            } catch {
                await MainActor.run { translatingLineID = nil }
            }
        }
    }

    private func toggleTranslation() {
        showTranslation.toggle()
        guard showTranslation, hasAPIKey else { return }
        translateWholeSong()
    }

    private func translateWholeSong() {
        guard let lyrics, !translatingAll else { return }
        // Skip if every non-empty line is already translated.
        let missing = lyrics.lines.contains {
            !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && translations[$0.id] == nil
        }
        guard missing else { return }

        translateAllFailed = false
        translatingAll = true
        let snapshot = lyrics.lines
        Task {
            do {
                let result = try await LyricsTranslator.translateAll(snapshot.map(\.text))
                await MainActor.run {
                    for (index, line) in snapshot.enumerated() {
                        let vi = result[index].trimmingCharacters(in: .whitespaces)
                        if !line.text.trimmingCharacters(in: .whitespaces).isEmpty, !vi.isEmpty {
                            translations[line.id] = vi
                        }
                    }
                    translatingAll = false
                    refreshSnapshotIfSaved()
                }
            } catch {
                await MainActor.run {
                    translatingAll = false
                    translateAllFailed = true
                }
            }
        }
    }

    private func toggleWord(_ word: String, line: String) {
        let savedID = library.toggleWord(word, line: line, song: song, meaning: nil)
        // If just saved and we have a key, fetch a short meaning in the background.
        guard let savedID, hasAPIKey else { return }
        Task {
            if let vi = try? await WordTranslator.translate(word, context: line) {
                await MainActor.run { library.setMeaning(vi, forWord: savedID) }
            }
        }
    }

    private static let wordPunctuation = CharacterSet(charactersIn: ".,!?;:\"“”‘’()[]{}<>—–…*~/\\")

    /// Strips surrounding punctuation but keeps inner apostrophes/hyphens
    /// (so "don't", "rock-n-roll" survive). Returns "" for pure punctuation.
    private func cleanedWord(_ token: String) -> String {
        token.trimmingCharacters(in: Self.wordPunctuation)
    }

    private func load() async {
        await MainActor.run { loadState = .loading }

        // Saved song? Use the offline snapshot — no lyrics/translate API calls.
        if let snap = library.lyricsSnapshot(forSongID: song.id) {
            let (restored, trans) = restoreLyrics(from: snap)
            await MainActor.run {
                lyrics = restored
                translations = trans
                showTranslation = snap.hasTranslation   // reveal the saved translation
                loadState = .ready
            }
            return
        }

        do {
            let result = try await LyricsService.fetch(for: song)
            await MainActor.run {
                lyrics = result
                loadState = .ready
                if showTranslation { translateWholeSong() }
            }
        } catch {
            let message: String
            if case SongServiceError.notFound = error {
                message = "Chưa có lời cho bài này trong kho LRCLIB. Thử một bản thu / phiên bản khác của bài hát nhé."
            } else {
                message = (error as? LocalizedError)?.errorDescription
                    ?? "Không tải được lời bài hát. Thử lại nhé."
            }
            await MainActor.run { loadState = .failed(message) }
        }
    }
}
