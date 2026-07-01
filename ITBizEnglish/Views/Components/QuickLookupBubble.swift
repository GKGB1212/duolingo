//
//  QuickLookupBubble.swift
//  ITBizEnglish
//
//  A Messenger-style floating "chat head" that's available app-wide. Tap it to
//  open a quick Vietnamese ⇄ English lookup panel — handy when you get stuck on
//  a word mid-Chat or mid-Self-Translate. A result can be saved straight into a
//  deck or copied, then the panel closed to keep studying.
//
//  Reuses DeckAIService (term → DeckWord) so the result IS already a saveable
//  card; no extra translation/save logic needed.
//

import SwiftUI
import UIKit

// MARK: - Floating bubble

struct QuickLookupBubble: View {
    @Bindable var decks: DeckStore

    // Position persists across launches: which edge + how far down (fraction).
    @AppStorage("itbiz.bubble.onRight") private var onRight = true
    @AppStorage("itbiz.bubble.yFraction") private var yFraction = 0.66

    @State private var committed: CGPoint?     // nil until first drag; else live center
    @State private var dragOffset: CGSize = .zero
    @State private var dragging = false
    @State private var showPanel = false

    private let size: CGFloat = 58
    private let margin: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let base = committed ?? restingCenter(in: geo.size)
            let shown = CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)

            bubble
                .position(shown)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            dragOffset = v.translation
                            if hypot(v.translation.width, v.translation.height) > 4 { dragging = true }
                        }
                        .onEnded { v in
                            let moved = hypot(v.translation.width, v.translation.height)
                            dragOffset = .zero
                            dragging = false
                            if moved < 8 {
                                showPanel = true                      // a tap → open the panel
                            } else {
                                let end = CGPoint(x: base.x + v.translation.width,
                                                  y: base.y + v.translation.height)
                                let snapped = snap(end, in: geo.size)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    committed = snapped
                                }
                                onRight = snapped.x > geo.size.width / 2
                                yFraction = Double(snapped.y / max(geo.size.height, 1))
                            }
                        }
                )
        }
        .ignoresSafeArea(.keyboard)   // don't hop when a keyboard opens underneath
        .sheet(isPresented: $showPanel) {
            QuickLookupPanel(decks: decks)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var bubble: some View {
        ZStack {
            Circle().fill(Color.brandEdge).offset(y: 3)       // 3D bottom lip
            Circle().fill(Color.brand)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2)
            Image(systemName: "character.book.closed.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: 7, x: 0, y: 4)
        .scaleEffect(dragging ? 1.12 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
    }

    // MARK: Geometry helpers

    private func restingCenter(in s: CGSize) -> CGPoint {
        CGPoint(x: onRight ? s.width - size/2 - margin : size/2 + margin,
                y: clampY(yFraction * s.height, in: s))
    }

    private func snap(_ p: CGPoint, in s: CGSize) -> CGPoint {
        let right = p.x > s.width / 2
        return CGPoint(x: right ? s.width - size/2 - margin : size/2 + margin,
                       y: clampY(p.y, in: s))
    }

    /// Keep the bubble clear of the nav/title area on top and the tab bar / input
    /// bar on the bottom.
    private func clampY(_ y: CGFloat, in s: CGSize) -> CGFloat {
        let minY = size/2 + 70
        let maxY = s.height - size/2 - 110
        return min(max(y, minY), max(minY, maxY))
    }
}

// MARK: - Lookup panel

/// The sheet shown when the bubble is tapped: a quick VN⇄EN dictionary lookup.
struct QuickLookupPanel: View {
    @Bindable var decks: DeckStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [DeckWord] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var savedIDs: Set<UUID> = []
    @State private var copiedID: UUID?
    @State private var speech = SpeechSynthesizer()
    @FocusState private var focused: Bool

    private let examples = ["triển khai", "khắc phục sự cố", "tối ưu hiệu năng", "đến hạn nộp"]

    private var hasKey: Bool { AppConfiguration.hasGeminiKey }
    private var canLookup: Bool {
        hasKey && !isLoading && !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Theme.Spacing.md) {
                header
                searchBar
                ScrollView {
                    content.padding(.bottom, Theme.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(Theme.Spacing.md)
        }
        .onAppear { focused = true }
        .onDisappear { speech.stop() }
    }

    // MARK: Header + search

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "character.book.closed.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.brand))
            VStack(alignment: .leading, spacing: 1) {
                Text("Tra cứu nhanh").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Text("Việt ⇄ Anh — gõ gì cũng được").font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.duoHare)
            }
            .buttonStyle(.plain)
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Gõ từ tiếng Việt hoặc tiếng Anh…", text: $query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
                .onSubmit(lookup)

            Button(action: lookup) {
                Group {
                    if isLoading { ProgressView().tint(.white) }
                    else { Image(systemName: "magnifyingglass").font(.headline.weight(.bold)) }
                }
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canLookup ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.duoHare)))
            }
            .buttonStyle(.plain)
            .disabled(!canLookup)
        }
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if !hasKey {
            noKeyCard
        } else if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.bold)).foregroundStyle(.duoRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.duoWrongFill))
        } else if results.isEmpty {
            emptyState
        } else {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(results) { resultCard($0) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(Color.brand.opacity(0.55))
            Text("Bí từ? Gõ tiếng Việt (hoặc tiếng Anh) vào ô trên để tra nhanh — rồi lưu vào bộ từ hoặc copy.")
                .font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
            FlowLayout(spacing: 8) {
                ForEach(examples, id: \.self) { ex in
                    Button { query = ex; lookup() } label: {
                        Text(ex)
                            .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.duoPolar))
                            .overlay(Capsule().strokeBorder(Color.duoSwan, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    private var noKeyCard: some View {
        Label("Chưa có API key — thêm key trong Cài đặt để dùng tra cứu AI.",
              systemImage: "key.slash.fill")
            .font(.callout.weight(.bold)).foregroundStyle(.duoRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.duoWrongFill))
    }

    // MARK: Result card

    private func resultCard(_ word: DeckWord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(word.word).font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                Button { speech.speak(word.word, id: word.id.uuidString) } label: {
                    Image(systemName: speech.speakingID == word.id.uuidString ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.title3).foregroundStyle(.brand)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            if !word.pronunciation.isEmpty {
                Text(word.pronunciation).font(.callout.monospaced()).foregroundStyle(.duoWolf)
            }
            Text(word.meaning).font(.body.weight(.semibold)).foregroundStyle(.duoInk)
            if !word.example.isEmpty {
                Text(word.example).font(.subheadline).italic().foregroundStyle(.duoWolf)
            }
            HStack(spacing: Theme.Spacing.sm) {
                saveMenu(word)
                copyButton(word)
                Spacer()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func saveMenu(_ word: DeckWord) -> some View {
        let saved = savedIDs.contains(word.id)
        return Menu {
            ForEach(decks.decks) { d in
                Button(d.title) { save(word, toDeckID: d.id) }
            }
            if !decks.decks.isEmpty { Divider() }
            Button { saveToQuickDeck(word) } label: {
                Label("Bộ mới «Tra cứu nhanh»", systemImage: "plus")
            }
        } label: {
            Label(saved ? "Đã lưu" : "Lưu vào bộ",
                  systemImage: saved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(saved ? AnyShapeStyle(Color.duoGreen) : AnyShapeStyle(Color.brand)))
        }
    }

    private func copyButton(_ word: DeckWord) -> some View {
        let copied = copiedID == word.id
        return Button {
            UIPasteboard.general.string = word.word
            copiedID = word.id
            Haptics.tap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedID == word.id { copiedID = nil }
            }
        } label: {
            Label(copied ? "Đã copy" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color.duoPolar))
                .overlay(Capsule().strokeBorder(Color.duoSwan, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func lookup() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isLoading, hasKey else { return }
        focused = false
        error = nil
        results = []
        savedIDs = []
        copiedID = nil
        isLoading = true
        Task {
            do {
                let words = try await DeckAIService().generateWords(from: q, includeBaseForms: true)
                await MainActor.run { results = words; isLoading = false }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? "Không tra được. Thử lại nhé."
                    isLoading = false
                }
            }
        }
    }

    private func save(_ word: DeckWord, toDeckID id: UUID) {
        decks.addWords([word], toDeck: id)
        savedIDs.insert(word.id)
        Haptics.tap()
    }

    /// Save into a shared "Tra cứu nhanh" deck, reusing it if it already exists.
    private func saveToQuickDeck(_ word: DeckWord) {
        let existing = decks.decks.first { $0.title == "Tra cứu nhanh" }
        let id = existing?.id ?? decks.createDeck(title: "Tra cứu nhanh").id
        save(word, toDeckID: id)
    }
}
