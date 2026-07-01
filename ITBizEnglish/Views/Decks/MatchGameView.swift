//
//  MatchGameView.swift
//  ITBizEnglish
//
//  "Ghép từ" — a continuous matching game. Two columns of tiles: English on the
//  left, Vietnamese on the right (each shuffled). Tap one from each side; a
//  correct pair pops and is replaced by new tiles. The refill engine guarantees
//  there is ALWAYS at least one matchable pair on the board (no dead ends), while
//  the two replacement tiles are NEVER each other's match — so no give-away pair
//  ever drops into the empty slots. Each new tile only matches a tile that was
//  already on the board, in a different row.
//

import SwiftUI

struct MatchGameView: View {
    @Bindable var store: DeckStore
    let deckID: UUID
    /// `.endless` = play forever; `.once` = each word appears once, then the game
    /// is won. Both use decoys so the board is a real matching hunt.
    var mode: Mode = .endless
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechSynthesizer()

    enum Mode { case endless, once }

    private struct Tile: Identifiable, Equatable {
        let id = UUID()        // view identity (so a replaced tile animates)
        let wordID: UUID       // which deck word this represents
        let text: String
    }
    private enum TileState { case normal, selected, matched, wrong }

    @State private var left: [Tile] = []      // English
    @State private var right: [Tile] = []     // Vietnamese
    @State private var selectedLeft: UUID?
    @State private var selectedRight: UUID?
    @State private var matched: Set<UUID> = []
    @State private var wrong: Set<UUID> = []
    @State private var locked = false
    @State private var score = 0
    @State private var streak = 0
    /// `.once` mode only: words not yet matched (each must be matched once).
    @State private var remaining: Set<UUID> = []
    @State private var goalCount = 0
    @State private var finished = false
    @State private var didSetup = false

    /// Only words the user has already learned are used in the matching game.
    private var words: [DeckWord] {
        (store.deck(id: deckID)?.learnedWords ?? []).filter {
            !$0.word.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.meaning.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    private var wordByID: [UUID: DeckWord] {
        Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var columnCount: Int { min(5, words.count) }
    /// Keep at least this many matchable pairs on the board at all times (endless).
    private var targetPairs: Int { min(3, columnCount) }

    var body: some View {
        ZStack {
            AppBackground()
            if finished {
                finishView
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    header
                    Text("Chạm một từ tiếng Anh rồi chạm nghĩa tiếng Việt tương ứng.")
                        .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.md)
                    columns
                    Spacer(minLength: 0)
                }
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .onAppear { if !didSetup { didSetup = true; setup() } }   // run once, never re-init mid-game
        .onDisappear { speech.stop() }
    }

    private var finishView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AnimatedGIF(name: "happy").frame(width: 180, height: 180)
            Text("Hoàn thành! 🎉").font(.title.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Bạn đã ghép xong tất cả từ đã học — \(score) lượt đúng.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
            VStack(spacing: Theme.Spacing.sm) {
                Button("Chơi lại") { restart() }.buttonStyle(.brand)
                Button("Xong") { dismiss() }
                    .font(.headline.weight(.heavy)).foregroundStyle(.duoWolf)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundStyle(.duoHare)
            }
            if mode == .once {
                // Progress toward matching every word once.
                DuoProgressBar(value: goalCount > 0 ? Double(score) / Double(goalCount) : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: score)
                Text("\(score)/\(goalCount)")
                    .font(.subheadline.weight(.heavy).monospacedDigit()).foregroundStyle(.duoWolf)
            } else {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.duoGreen)
                    Text("\(score)").monospacedDigit()
                }
                .font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                if streak >= 2 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)").monospacedDigit()
                    }
                    .font(.headline.weight(.heavy)).foregroundStyle(.duoGold)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Columns

    private var columns: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(left) { tile in
                    tileView(tile, state: state(tile, selected: selectedLeft)) { tap(tile, side: .left) }
                }
            }
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(right) { tile in
                    tileView(tile, state: state(tile, selected: selectedRight)) { tap(tile, side: .right) }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func state(_ tile: Tile, selected: UUID?) -> TileState {
        if matched.contains(tile.id) { return .matched }
        if wrong.contains(tile.id) { return .wrong }
        if selected == tile.id { return .selected }
        return .normal
    }

    private func tileView(_ tile: Tile, state: TileState, _ action: @escaping () -> Void) -> some View {
        let fill: Color
        let border: Color
        let fg: Color
        switch state {
        case .normal:   fill = .duoPolar;       border = .duoSwan;  fg = .duoInk
        case .selected: fill = Color.brand.opacity(0.15); border = .brand; fg = .duoInk
        case .matched:  fill = .duoCorrectFill; border = .duoGreen; fg = .duoCorrectText
        case .wrong:    fill = .duoWrongFill;   border = .duoRed;   fg = .duoWrongText
        }
        return Button(action: action) {
            Text(tile.text)
                .font(.callout.weight(.bold)).foregroundStyle(fg)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.choice, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.choice, style: .continuous)
                    .strokeBorder(border, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(locked || state == .matched)
        .correctCelebration(trigger: state == .matched, cornerRadius: Theme.Radius.choice)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Setup

    private func setup() {
        let ws = words
        guard ws.count >= 2 else { left = []; right = []; return }
        let k = columnCount

        if mode == .once {
            // `.once`: each word must be matched exactly once; the board draws only
            // from the not-yet-matched pool and shrinks toward a win. It still gets
            // the same decoy board below so it plays like a real matching game.
            remaining = Set(ws.map(\.id))
            goalCount = ws.count
        }

        // Build a board with `pairCount` solvable pairs plus *disjoint* decoys on
        // each side — English tiles whose meaning is off-board, and meanings whose
        // English is off-board. Those decoys are what force the player to hunt for
        // the match instead of tapping any two tiles. The two columns are shuffled
        // independently. A clean board needs (2k - pairCount) distinct words; if the
        // deck is smaller we trade decoys for pairs (a tiny deck becomes all-pairs).
        let n = ws.count
        let pairCount = min(k, max(min(targetPairs, k), 2 * k - n))
        let decoyEach = k - pairCount
        let shuffled = ws.shuffled()
        let pairWords   = Array(shuffled.prefix(pairCount))
        let decoyPool   = Array(shuffled.dropFirst(pairCount))
        let leftDecoys  = Array(decoyPool.prefix(decoyEach))
        let rightDecoys = Array(decoyPool.dropFirst(decoyEach).prefix(decoyEach))

        left  = (pairWords + leftDecoys).shuffled().map  { Tile(wordID: $0.id, text: $0.word) }
        right = (pairWords + rightDecoys).shuffled().map { Tile(wordID: $0.id, text: $0.meaning) }
    }

    private func restart() {
        selectedLeft = nil; selectedRight = nil
        matched = []; wrong = []
        score = 0; streak = 0; locked = false
        finished = false; goalCount = 0
        setup()
    }

    // MARK: - Tapping

    private enum Side { case left, right }

    private func tap(_ tile: Tile, side: Side) {
        guard !locked else { return }
        Haptics.tap()
        switch side {
        case .left:  selectedLeft = (selectedLeft == tile.id) ? nil : tile.id
        case .right: selectedRight = (selectedRight == tile.id) ? nil : tile.id
        }
        evaluate()
    }

    private func evaluate() {
        guard let l = selectedLeft, let r = selectedRight,
              let lt = left.first(where: { $0.id == l }),
              let rt = right.first(where: { $0.id == r }) else { return }

        if lt.wordID == rt.wordID {
            locked = true
            score += 1
            withAnimation(.snappy) { streak += 1 }
            matched.insert(l); matched.insert(r)
            SoundFX.correct()
            speech.speak(lt.text, id: lt.id.uuidString)
            if mode == .once { remaining.remove(lt.wordID) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {   // let the pop+shine play
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    refill(leftID: l, rightID: r)
                }
                matched.remove(l); matched.remove(r)
                selectedLeft = nil; selectedRight = nil
                locked = false
                if mode == .once, left.isEmpty, right.isEmpty {
                    finished = true
                    SoundFX.completed()
                }
            }
        } else {
            locked = true
            streak = 0
            wrong.insert(l); wrong.insert(r)
            SoundFX.wrong()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation { wrong.remove(l); wrong.remove(r) }
                selectedLeft = nil; selectedRight = nil
                locked = false
            }
        }
    }

    // MARK: - Refill engine

    /// Refill the two slots a just-matched pair vacated. Shared by both modes.
    ///
    /// The replacements are chosen so the new English tile and the new Vietnamese
    /// tile are NEVER each other's match — that give-away "fresh pair sitting side
    /// by side" was the bug. Instead, ONE new tile completes an existing on-board
    /// decoy into a pair (so the board always keeps a solvable pair, with the
    /// partner in a *different* row), and the OTHER becomes a fresh decoy (keeping
    /// the hunt alive). Orientation is randomised for variety.
    ///
    /// `.endless` draws fresh tiles from the whole deck and never empties.
    /// `.once` draws only from words still `remaining` (each matched exactly once)
    /// and, once the pool is spent, shrinks the board — when both columns empty the
    /// game is won.
    private func refill(leftID: UUID, rightID: UUID) {
        guard let li = left.firstIndex(where: { $0.id == leftID }),
              let ri = right.firstIndex(where: { $0.id == rightID }) else { return }
        let matchedID = left[li].wordID

        // Word-ids that remain on each side once the matched tiles are gone.
        let leftIDs  = Set(left.indices.filter  { $0 != li }.map { left[$0].wordID })
        let rightIDs = Set(right.indices.filter { $0 != ri }.map { right[$0].wordID })
        let onBoard   = leftIDs.union(rightIDs)
        let leftOnly  = leftIDs.subtracting(rightIDs)   // English whose meaning is off-board
        let rightOnly = rightIDs.subtracting(leftIDs)   // meaning whose English is off-board

        func w(_ id: UUID) -> DeckWord? { wordByID[id] }
        // Fresh candidates: not on the board and not the word we just cleared. In
        // `.once` they must also still need matching, so the board can drain to a win.
        let freshPool = words
            .filter { !onBoard.contains($0.id) && $0.id != matchedID }
            .filter { mode == .endless || remaining.contains($0.id) }
            .shuffled()
        let fresh = freshPool.first

        // Right slot completes a left-only decoy into a pair; left slot is a fresh
        // decoy (or, when there are no fresh words left, completes a right-only
        // decoy too — both new tiles still pair with *existing* tiles, not each other).
        func completeLeftDecoy() -> (DeckWord, DeckWord)? {
            guard let y = leftOnly.randomElement(), let yw = w(y) else { return nil }
            if let f = fresh { return (f, yw) }
            if let x = rightOnly.randomElement(), let xw = w(x) { return (xw, yw) }
            return nil
        }
        // Mirror image: left slot completes a right-only decoy, right slot is fresh.
        func completeRightDecoy() -> (DeckWord, DeckWord)? {
            guard let x = rightOnly.randomElement(), let xw = w(x) else { return nil }
            if let f = fresh { return (xw, f) }
            if let y = leftOnly.randomElement(), let yw = w(y) { return (xw, yw) }
            return nil
        }

        let attempt = Bool.random()
            ? (completeLeftDecoy() ?? completeRightDecoy())
            : (completeRightDecoy() ?? completeLeftDecoy())

        if let pick = attempt {
            left[li]  = Tile(wordID: pick.0.id, text: pick.0.word)
            right[ri] = Tile(wordID: pick.1.id, text: pick.1.meaning)
            return
        }

        // No decoy to complete ⇒ the board is all-pairs (it still has k-1 solvable
        // pairs, so it stays playable whatever we do here).
        if freshPool.count >= 2 {
            // Drop in two fresh, non-matching decoys to re-introduce the hunt.
            left[li]  = Tile(wordID: freshPool[0].id, text: freshPool[0].word)
            right[ri] = Tile(wordID: freshPool[1].id, text: freshPool[1].meaning)
        } else if mode == .endless {
            // Endless never shrinks: recycle two different words (avoid duplicate
            // tiles; distinct ids keep the new tiles from being a match).
            let a = words.first { !leftIDs.contains($0.id) } ?? words.randomElement()!
            let b = words.first { !rightIDs.contains($0.id) && $0.id != a.id }
                ?? words.first { $0.id != a.id } ?? a
            left[li]  = Tile(wordID: a.id, text: a.word)
            right[ri] = Tile(wordID: b.id, text: b.meaning)
        } else if let f = fresh {
            // `.once` tail: exactly one word left to introduce — bring it as a full
            // pair (a brief give-away, but it is literally the last new word).
            left[li]  = Tile(wordID: f.id, text: f.word)
            right[ri] = Tile(wordID: f.id, text: f.meaning)
        } else {
            // `.once` and nothing left to add: shrink the board toward the win.
            left.remove(at: li)
            right.remove(at: ri)
        }
    }
}
