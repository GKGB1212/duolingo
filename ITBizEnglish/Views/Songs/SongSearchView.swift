//
//  SongSearchView.swift
//  ITBizEnglish
//
//  The "Bài hát" tab: search Apple's catalog for a song, sample its 30-second
//  preview right in the list, then tap a row to open the full lyrics. This
//  feature is intentionally separate from the vocabulary/deck system.
//

import SwiftUI

/// Every screen reachable from the Bài hát tab, driven by one navigation path.
/// Using a single typed route (instead of mixing `navigationDestination(for:)`
/// with `navigationDestination(isPresented:)`, which SwiftUI handles unreliably)
/// keeps pushes — search → lyrics, library → a song's saved words — working.
enum SongRoute: Hashable {
    case library
    case lyrics(SongResult)
    case savedWords(SongResult)
}

struct SongSearchView: View {
    @State private var query = ""
    @State private var results: [SongResult] = []
    @State private var phase: Phase = .idle
    @State private var player = SongPreviewPlayer()
    @State private var searchTask: Task<Void, Never>?
    @State private var path: [SongRoute] = []

    private enum Phase {
        case idle, loading, loaded, empty, failed(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AppBackground()
                content
            }
            .navigationTitle("Bài hát")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.library) } label: {
                        Image(systemName: "bookmark.fill")
                    }
                    .accessibilityLabel("Đã lưu")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Tìm bài hát hoặc ca sĩ…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { _, new in
                if new.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchTask?.cancel()
                    results = []
                    phase = .idle
                }
            }
            .navigationDestination(for: SongRoute.self) { route in
                switch route {
                case .library:              SongLibraryView()
                case .lyrics(let song):     SongLyricsView(song: song)
                case .savedWords(let song): SongSavedWordsView(song: song)
                }
            }
            .onDisappear { player.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:            idleState
        case .loading:         loadingState
        case .empty:           emptyState
        case .failed(let msg): errorState(msg)
        case .loaded:          resultsList
        }
    }

    // MARK: - States

    private var idleState: some View {
        infoState(icon: "music.note.list",
                  title: "Học tiếng Anh qua bài hát",
                  message: "Gõ tên bài hát hoặc ca sĩ rồi nhấn tìm. Bấm ▶︎ để nghe thử 30 giây, chọn bài để xem toàn bộ lời.")
    }

    private var loadingState: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text("Đang tìm…").font(.callout.weight(.bold)).foregroundStyle(.duoWolf)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        infoState(icon: "magnifyingglass",
                  title: "Không tìm thấy",
                  message: "Không có kết quả cho “\(query)”. Thử từ khoá khác — kèm tên ca sĩ thường ra đúng hơn.")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.duoRed)
            Text(message)
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
            Button("Thử lại") { runSearch() }
                .buttonStyle(.duoBlue)
                .frame(maxWidth: 200)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon).font(.system(size: 46)).foregroundStyle(.brand)
            Text(title).font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
            Text(message)
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(results) { song in
                    HStack(spacing: 0) {
                        NavigationLink(value: SongRoute.lyrics(song)) {
                            SongCardRow(song: song, trailingInset: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay(alignment: .trailing) {
                        if song.previewURL != nil {
                            previewButton(song)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
    }

    /// Floats the ▶︎/⏸ over the row's trailing edge so it stays tappable on its
    /// own without triggering the row's navigation link.
    private func previewButton(_ song: SongResult) -> some View {
        Button {
            Haptics.tap()
            player.toggle(song)
        } label: {
            Image(systemName: player.playingID == song.id ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.brand)
                .padding(.trailing, Theme.Spacing.md + 18)   // sit left of the chevron
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private func runSearch() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searchTask?.cancel()
        player.stop()
        phase = .loading
        searchTask = Task {
            do {
                let found = try await ITunesSearchService.search(term)
                if Task.isCancelled { return }
                await MainActor.run {
                    results = found
                    phase = found.isEmpty ? .empty : .loaded
                }
            } catch {
                if Task.isCancelled { return }
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "Không tìm được. Kiểm tra mạng và thử lại."
                await MainActor.run { phase = .failed(message) }
            }
        }
    }
}

// MARK: - Row

/// Shared song row card (artwork + title/artist + chevron), reused by the search
/// results and the saved-songs list. `trailingInset` reserves space on the right
/// for an overlaid control (the floating preview button in search results).
struct SongCardRow: View {
    let song: SongResult
    var artworkSize: CGFloat = 56
    var trailingInset: CGFloat = 0
    /// Optional pill on the trailing edge (e.g. a saved-word count).
    var badge: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            SongArtwork(url: song.artworkURL, size: artworkSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                Text(song.artist).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.caption.weight(.heavy)).foregroundStyle(.brand)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.brand.opacity(0.12)))
            }
            if trailingInset > 0 { Color.clear.frame(width: trailingInset) }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold)).foregroundStyle(.duoSwan)
        }
        .padding(Theme.Spacing.sm)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

// MARK: - Shared artwork view (reused by the lyrics screen)

struct SongArtwork: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                placeholder.overlay(ProgressView().tint(.duoWolf))
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.duoSwan, lineWidth: 1.5))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.duoPolar)
            .overlay(Image(systemName: "music.note")
                .font(.system(size: size * 0.35)).foregroundStyle(.duoHare))
    }
}

#Preview {
    SongSearchView()
}
