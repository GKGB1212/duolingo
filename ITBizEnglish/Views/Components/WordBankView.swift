//
//  WordBankView.swift
//  ITBizEnglish
//
//  The shared "Ghép từ" word-bank exercise: a Vietnamese sentence on top, then
//  a worksheet-style answer zone where the user assembles the English sentence
//  by tapping (or dragging) word tiles up from the bank below. Used by both
//  Self-Translate (PracticeWriteView) and the Translator (TranslationView).
//

import SwiftUI

struct WordBankView<Footer: View>: View {
    /// The prompt shown on top.
    private let vietnamese: String
    /// The correct English sentence to rebuild.
    private let target: String
    /// Extra words mixed into the bank to make it harder.
    private let distractors: [String]
    /// Optional speech engine — when set, a speaker reads the answer aloud.
    private let speech: SpeechSynthesizer?
    /// Called each time the user taps "Kiểm tra": `(correct, assembledAttempt)`.
    private let onChecked: (Bool, String) -> Void
    /// Host actions shown after a correct answer (e.g. "Tiếp tục" / "Done").
    private let successFooter: () -> Footer

    init(vietnamese: String,
         target: String,
         distractors: [String] = [],
         speech: SpeechSynthesizer? = nil,
         onChecked: @escaping (Bool, String) -> Void = { _, _ in },
         @ViewBuilder successFooter: @escaping () -> Footer) {
        self.vietnamese = vietnamese
        self.target = target
        self.distractors = distractors
        self.speech = speech
        self.onChecked = onChecked
        self.successFooter = successFooter
    }

    private struct Tile: Identifiable, Equatable { let id = UUID(); let text: String }
    @State private var bank: [Tile] = []
    @State private var chosen: [Tile] = []
    @State private var result: Bool? = nil          // nil = chưa kiểm tra
    @State private var bumpedIDs: Set<UUID> = []     // staggered pop on correct
    @State private var built = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            promptBanner
            instruction
            answerZone
            bankZone
            if let result {
                resultBanner(result)
            } else {
                Button("Kiểm tra") { check() }
                    .buttonStyle(.duoPrimary(enabled: !chosen.isEmpty))
                    .disabled(chosen.isEmpty)
            }
        }
        .onAppear { if !built { built = true; build() } }
        .onChange(of: target) { _, _ in build() }
    }

    // MARK: - Prompt

    private var promptBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "quote.opening")
                .font(.title3.weight(.black))
                .foregroundStyle(.duoIndigo)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tiếng Việt")
                    .font(.caption.weight(.heavy)).textCase(.uppercase)
                    .foregroundStyle(.duoWolf)
                Text(vietnamese)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.duoInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var instruction: some View {
        Label("Chạm các từ theo đúng thứ tự để tạo câu", systemImage: "hand.tap.fill")
            .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Answer zone (worksheet)

    private var zoneBorder: Color {
        switch result {
        case .some(true):  return .duoOkBorder
        case .some(false): return .duoWrongBorder
        case .none:        return .duoSwan
        }
    }

    private var answerZone: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return FlowLayout(spacing: 8) {
            ForEach(chosen) { tile in tileView(tile, inAnswer: true) }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(
            ZStack {
                shape.fill(Color.duoPolar)
                WritingLines()
                if chosen.isEmpty {
                    Text("Chạm vào từ bên dưới…")
                        .font(.callout.weight(.bold)).foregroundStyle(.duoHare)
                }
            }
        )
        .overlay(shape.strokeBorder(zoneBorder, lineWidth: 2))
        .overlay(alignment: .bottom) {
            shape.strokeBorder(zoneBorder, lineWidth: 2)
                .mask(Rectangle().frame(height: 4).frame(maxHeight: .infinity, alignment: .bottom))
        }
        .contentShape(Rectangle())
        // Drop into empty space → append to the end of the answer.
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let id = UUID(uuidString: s) else { return false }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { moveToChosen(id: id, before: nil) }
            return true
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chosen)
    }

    private var bankZone: some View {
        FlowLayout(spacing: 8) {
            ForEach(bank) { tile in tileView(tile, inAnswer: false) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        // Drop here → return the tile to the bank.
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let id = UUID(uuidString: s) else { return false }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { moveToBank(id: id) }
            return true
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bank)
    }

    @ViewBuilder
    private func tileView(_ tile: Tile, inAnswer: Bool) -> some View {
        let correct = result == true && inAnswer
        let button = Button {
            guard result == nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if inAnswer { moveToBank(id: tile.id) } else { moveToChosen(id: tile.id, before: nil) }
            }
        } label: {
            Text(tile.text)
                .font(.body.weight(.bold)).foregroundStyle(correct ? .duoOkText : .duoInk)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(correct ? Color.duoOkFill : Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(correct ? Color.duoOkBorder : Color.duoSwan, lineWidth: 2))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(correct ? Color.duoOkBorder : Color.duoSwan, lineWidth: 2)
                        .mask(Rectangle().frame(height: 3).frame(maxHeight: .infinity, alignment: .bottom))
                }
                .correctCelebration(trigger: bumpedIDs.contains(tile.id), cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .draggable(tile.id.uuidString)

        if inAnswer {
            // Reorder: dropping another tile onto this one inserts it just before.
            button.dropDestination(for: String.self) { items, _ in
                guard let s = items.first, let id = UUID(uuidString: s) else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { moveToChosen(id: id, before: tile.id) }
                return true
            }
        } else {
            button
        }
    }

    // MARK: - Result

    @ViewBuilder
    private func resultBanner(_ ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(ok ? "Chính xác! 🎉" : "Chưa đúng rồi", systemImage: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.headline.weight(.heavy))
                .foregroundStyle(ok ? .duoGreen : .duoWrongText)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ok ? "CÂU CỦA BẠN" : "ĐÁP ÁN ĐÚNG")
                        .font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                    Text(target)
                        .font(.body.weight(.bold)).foregroundStyle(.duoInk)
                        .textSelection(.enabled)
                }
                Spacer()
                if let speech {
                    Button { speech.speak(target, id: "wb-\(target.hashValue)") } label: {
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.duoIndigo)
                    }
                    .buttonStyle(.plain)
                }
            }

            if ok {
                successFooter()
            } else {
                Button("Thử lại") { build() }
                    .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(ok ? Color.duoOkFill : Color.duoWrongFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(ok ? Color.duoOkBorder : Color.duoWrongBorder, lineWidth: 2))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Tile moves (shared by tap + drag/drop)

    private func removeTile(id: UUID) -> Tile? {
        if let i = chosen.firstIndex(where: { $0.id == id }) { return chosen.remove(at: i) }
        if let i = bank.firstIndex(where: { $0.id == id }) { return bank.remove(at: i) }
        return nil
    }

    /// Moves a tile into `chosen`, inserting before `targetID` or appending when nil.
    private func moveToChosen(id: UUID, before targetID: UUID?) {
        guard result == nil, id != targetID, let tile = removeTile(id: id) else { return }
        if let targetID, let idx = chosen.firstIndex(where: { $0.id == targetID }) {
            chosen.insert(tile, at: idx)
        } else {
            chosen.append(tile)
        }
    }

    private func moveToBank(id: UUID) {
        guard result == nil, let i = chosen.firstIndex(where: { $0.id == id }) else { return }
        bank.append(chosen.remove(at: i))
    }

    // MARK: - Logic

    private func build() {
        let targetWords = target.split(separator: " ").map(String.init)
        let extras = distractors.filter { !targetWords.contains($0) }.prefix(4)
        withAnimation {
            bank = (targetWords + extras).shuffled().map { Tile(text: $0) }
            chosen = []
            result = nil
            bumpedIDs = []
        }
    }

    private func check() {
        let attempt = chosen.map(\.text).joined(separator: " ")
        let ok = normalized(attempt) == normalized(target)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { result = ok }
        if ok {
            SoundFX.correct()
            for (i, tile) in chosen.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { bumpedIDs.insert(tile.id) }
            }
        } else {
            SoundFX.wrong()
        }
        onChecked(ok, attempt)
    }

    private func normalized(_ str: String) -> String {
        str.lowercased()
           .components(separatedBy: CharacterSet.alphanumerics.inverted)
           .filter { !$0.isEmpty }
           .joined(separator: " ")
    }
}

extension WordBankView where Footer == EmptyView {
    init(vietnamese: String,
         target: String,
         distractors: [String] = [],
         speech: SpeechSynthesizer? = nil,
         onChecked: @escaping (Bool, String) -> Void = { _, _ in }) {
        self.init(vietnamese: vietnamese, target: target, distractors: distractors,
                  speech: speech, onChecked: onChecked, successFooter: { EmptyView() })
    }
}

// MARK: - Worksheet rule lines

/// Faint, evenly spaced horizontal lines behind the answer zone so each row of
/// tiles appears to rest on a writing line — the signature word-bank look.
private struct WritingLines: View {
    var rowHeight: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let count = max(1, Int(geo.size.height / rowHeight))
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Spacer()
                        Capsule().fill(Color.duoSwan).frame(height: 2).opacity(0.6)
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.horizontal, 6)
        }
        .allowsHitTesting(false)
    }
}
