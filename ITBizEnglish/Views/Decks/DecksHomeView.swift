//
//  DecksHomeView.swift
//  ITBizEnglish
//
//  Lists all decks (Memrise-style courses) with progress, plus entry points to
//  create a deck or import one. Tapping a deck opens its DeckDashboardView.
//

import SwiftUI

struct DecksHomeView: View {
    @Bindable var store: DeckStore
    @State private var showNewDeck = false
    @State private var showImport = false
    @State private var newTitle = ""

    var body: some View {
        ZStack {
            AppBackground()
            if store.decks.isEmpty {
                ContentUnavailableView {
                    Label("No courses yet", systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text("Create a deck or import words from JSON to start learning.")
                } actions: {
                    Button("Import JSON") { showImport = true }
                        .buttonStyle(.duoGreen)
                        .frame(maxWidth: 220)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(store.decks) { deck in
                            NavigationLink {
                                DeckDashboardView(store: store, deckID: deck.id)
                            } label: {
                                DeckRow(deck: deck)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation { store.deleteDeck(id: deck.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .navigationTitle("Courses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showNewDeck = true } label: { Label("New deck", systemImage: "plus") }
                    Button { showImport = true } label: { Label("Import JSON / AI", systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus") }
            }
        }
        .alert("New deck", isPresented: $showNewDeck) {
            TextField("Deck title", text: $newTitle)
            Button("Create") {
                let t = newTitle.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.createDeck(title: t) }
                newTitle = ""
            }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .sheet(isPresented: $showImport) {
            ImportView(store: store)
        }
    }
}

private struct DeckRow: View {
    let deck: WordDeck

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(deck.accent)
                    .frame(width: 52, height: 52)
                Image(systemName: deck.icon).foregroundStyle(.white).font(.title3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(deck.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                Text("\(deck.masteredCount)/\(deck.total) mastered")
                    .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                DuoProgressBar(value: deck.progress, tint: deck.accent, height: 10)
            }
            if deck.dueReviewCount > 0 {
                Text("\(deck.dueReviewCount)")
                    .font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(.duoGold))
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.duoSwan)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

// MARK: - Per-deck dashboard

struct DeckDashboardView: View {
    @Bindable var store: DeckStore
    let deckID: UUID

    @State private var showLearn = false
    @State private var showReview = false
    @State private var showDifficult = false
    @State private var showPreview = false
    @State private var showGame = false
    @State private var matchLaunch: MatchLaunch?
    @State private var showGamePicker = false
    @State private var showImport = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showIconPicker = false
    @State private var editingWord: DeckWord?
    @State private var speech = SpeechSynthesizer()
    @State private var mascot = AnimatedGIF.randomWaiting()

    private var deck: WordDeck? { store.deck(id: deckID) }

    var body: some View {
        ZStack {
            AppBackground()
            if let deck {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.sm) {
                            AnimatedGIF(name: mascot)
                                .frame(width: 96, height: 110)
                            MasteryRing(
                                progress: deck.progress,
                                centerText: "\(deck.masteredCount)",
                                centerSubtitle: "/ \(deck.total) từ"
                            )
                            .frame(width: 130, height: 130)
                        }
                        .padding(.top)

                        statsRow(deck)
                        actionButtons(deck)
                        wordList(deck)
                    }
                    .padding(Theme.Spacing.md)
                }
            } else {
                ContentUnavailableView("Deck not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(deck?.title ?? "Deck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImport = true } label: { Label("Add words", systemImage: "plus") }
                    Button { renameText = deck?.title ?? ""; showRename = true } label: {
                        Label("Rename course", systemImage: "pencil")
                    }
                    Button { showIconPicker = true } label: {
                        Label("Đổi icon & màu", systemImage: "paintbrush.fill")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .fullScreenCover(isPresented: $showLearn) {
            LearningSessionView(store: store, deckID: deckID, mode: .learn)
        }
        .fullScreenCover(isPresented: $showReview) {
            LearningSessionView(store: store, deckID: deckID, mode: .review)
        }
        .fullScreenCover(isPresented: $showDifficult) {
            LearningSessionView(store: store, deckID: deckID, mode: .difficult)
        }
        .fullScreenCover(isPresented: $showPreview) {
            DeckPreviewView(store: store, deckID: deckID)
        }
        .fullScreenCover(isPresented: $showGame) {
            DeckGameView(store: store, deckID: deckID)
        }
        .fullScreenCover(item: $matchLaunch) { launch in
            MatchGameView(store: store, deckID: deckID, mode: launch.mode)
        }
        .overlay { gamePickerOverlay }
        .sheet(isPresented: $showImport) {
            ImportView(store: store, fixedDeckID: deckID)
        }
        .sheet(item: $editingWord) { word in
            DeckWordEditorView(store: store, deckID: deckID, word: word)
        }
        .sheet(isPresented: $showIconPicker) {
            IconColorPicker(icon: deck?.icon ?? "leaf.fill",
                            colorHex: deck?.colorHex ?? 0x58CC02) { icon, color in
                store.setAppearance(icon: icon, colorHex: color, forDeck: deckID)
            }
        }
        .alert("Rename course", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.renameDeck(id: deckID, to: t) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The centered "Trò chơi" popup (dimmed backdrop + a small card that pops in).
    @ViewBuilder
    private var gamePickerOverlay: some View {
        if showGamePicker {
            ZStack {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { showGamePicker = false } }
                GamePickerCard(
                    onChoose: chooseGame,
                    onClose: { withAnimation(.snappy) { showGamePicker = false } }
                )
                .frame(maxWidth: 420)
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .zIndex(10)
        }
    }

    /// Close the popup, then launch the chosen game (a full-screen cover can't be
    /// presented in the same frame the popup is dismissed).
    private func chooseGame(_ choice: GameChoice) {
        withAnimation(.snappy) { showGamePicker = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            switch choice {
            case .speed:        showGame = true
            case .matchEndless: matchLaunch = MatchLaunch(mode: .endless)
            case .matchOnce:    matchLaunch = MatchLaunch(mode: .once)
            }
        }
    }

    // MARK: - Action buttons (Learn / Review / Game)

    private func actionButtons(_ deck: WordDeck) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button { showLearn = true } label: {
                Label("Học từ mới", systemImage: "play.fill")
            }
            .buttonStyle(.duoPrimary(enabled: !deck.studyableWords.isEmpty))
            .disabled(deck.studyableWords.isEmpty)

            HStack(spacing: Theme.Spacing.sm) {
                let canReview = !deck.reviewableWords.isEmpty
                Button { showReview = true } label: {
                    Label(canReview ? "Ôn lại (\(deck.reviewableWords.count))" : "Ôn lại",
                          systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.duo(.duoGold, edge: .duoGoldEdge, enabled: canReview))
                .disabled(!canReview)

                let canDifficult = !deck.difficultWords.isEmpty
                Button { showDifficult = true } label: {
                    Label(canDifficult ? "Từ khó (\(deck.difficultCount))" : "Từ khó",
                          systemImage: "star.fill")
                }
                .buttonStyle(.duo(.duoRed, edge: .duoRedEdge, enabled: canDifficult))
                .disabled(!canDifficult)
            }

            let canPlay = deck.learnedWords.count >= 4
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showGamePicker = true }
            } label: {
                Label("Trò chơi", systemImage: "gamecontroller.fill")
            }
            .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge, enabled: canPlay))
            .disabled(!canPlay)

            if deck.studyableWords.isEmpty {
                Text("Đã học hết — quay lại khi có từ cần ôn nhé! 🎉")
                    .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
            }
        }
    }

    private func statsRow(_ deck: WordDeck) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatTile(value: "\(deck.studyableWords.count)", label: "Cần học",
                     systemImage: "tray.full.fill", color: .duoBlue)
            StatTile(value: "\(deck.dueReviewCount)", label: "Cần ôn",
                     systemImage: "clock.arrow.circlepath", color: .duoGold)
            StatTile(value: "\(deck.masteredCount)", label: "Thuộc",
                     systemImage: "checkmark.seal.fill", color: .duoGreen)
        }
    }

    private func wordList(_ deck: WordDeck) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("TỪ VỰNG").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                if deck.difficultCount > 0 {
                    Label("\(deck.difficultCount) từ khó", systemImage: "star.fill")
                        .font(.caption2.weight(.bold)).foregroundStyle(.duoGold)
                }
                Spacer()
                if !deck.words.isEmpty {
                    Button { showPreview = true } label: {
                        Label("Xem trước", systemImage: "rectangle.stack.fill")
                            .font(.caption.weight(.heavy)).foregroundStyle(.duoBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(deck.words.enumerated()), id: \.element.id) { idx, w in
                    wordRow(w)
                    if idx < deck.words.count - 1 {
                        Divider().overlay(Color.duoSwan).padding(.leading, 56)
                    }
                }
            }
            .duoCard(cornerRadius: Theme.Radius.card)
        }
    }

    private func wordRow(_ w: DeckWord) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { speech.speak(w.word, id: w.id.uuidString) } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2).foregroundStyle(.duoBlue)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(w.word).font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Text(w.meaning).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf).lineLimit(2)
            }
            Spacer()
            Button {
                withAnimation { store.toggleDifficult(w.id, inDeck: deckID) }
            } label: {
                Image(systemName: w.isDifficult ? "star.fill" : "star")
                    .font(.title3).foregroundStyle(w.isDifficult ? .duoGold : .duoSwan)
            }
            .buttonStyle(.plain)

            GrowthBadge(progress: w.correctCount)
                .scaleEffect(0.62)
                .frame(width: 38, height: 44)
        }
        .padding(.vertical, 14).padding(.horizontal, Theme.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture { editingWord = w }
    }
}

// MARK: - Game picker

enum GameChoice { case speed, matchEndless, matchOnce }

/// Carries the chosen match mode INTO `.fullScreenCover(item:)` so presentation
/// and mode can never disagree (an `isPresented` + separate `@State mode` could
/// present with a stale mode).
struct MatchLaunch: Identifiable { let id = UUID(); let mode: MatchGameView.Mode }

/// The "Trò chơi" popup card: pick a game, and for Ghép từ pick a mode. A small
/// centered card (shown over a dimmed backdrop), not a bottom sheet.
private struct GamePickerCard: View {
    let onChoose: (GameChoice) -> Void
    let onClose: () -> Void

    private enum Stage { case games, matchMode }
    @State private var stage: Stage = .games

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                if stage == .matchMode {
                    Button { withAnimation(.snappy) { stage = .games } } label: {
                        Image(systemName: "chevron.left").font(.headline.weight(.bold)).foregroundStyle(.duoWolf)
                    }
                    .buttonStyle(.plain)
                }
                Text(stage == .games ? "Trò chơi" : "Chọn chế độ")
                    .font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.duoHare)
                }
                .buttonStyle(.plain)
            }

            if stage == .games {
                gameButton("Speed Review", subtitle: "Trả lời nhanh các từ đã học",
                           icon: "bolt.fill", color: .duoIndigo, edge: .duoIndigoEdge) {
                    onChoose(.speed)
                }
                gameButton("Ghép từ", subtitle: "Nối từ Anh – Việt",
                           icon: "puzzlepiece.fill", color: .duoBlue, edge: .duoBlueEdge) {
                    withAnimation(.snappy) { stage = .matchMode }
                }
            } else {
                gameButton("Vô tận", subtitle: "Chơi không giới hạn",
                           icon: "infinity", color: .duoBlue, edge: .duoBlueEdge) {
                    onChoose(.matchEndless)
                }
                gameButton("Bình thường", subtitle: "Ghép hết các từ là thắng",
                           icon: "flag.checkered", color: .duoGreen, edge: .duoGreenEdge) {
                    onChoose(.matchOnce)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Color.duoSwan, lineWidth: 2))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    /// A self-styled option row (NOT DuoButtonStyle, which force-uppercases the
    /// label and adds no horizontal padding) — keeps a 3D lip but controls its own
    /// fonts + even internal padding.
    private func gameButton(_ title: String, subtitle: String, icon: String,
                            color: Color, edge: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon).font(.title3.weight(.bold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline.weight(.heavy))
                    Text(subtitle).font(.caption.weight(.semibold)).opacity(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).fill(edge).offset(y: 4)
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).fill(color)
                }
            )
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { DecksHomeView(store: DeckStore()) }
}
