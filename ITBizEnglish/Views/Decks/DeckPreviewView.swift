//
//  DeckPreviewView.swift
//  ITBizEnglish
//
//  A read-only "xem trước" browse of every word in a course, first → last.
//  Swipe (or use the buttons) through big flashcards showing each word's full
//  definition: the English word, pronunciation, part of speech, Vietnamese
//  meaning and an example sentence. No scoring, no spaced-repetition — purely
//  for looking over the vocabulary before (or instead of) studying it.
//

import SwiftUI

struct DeckPreviewView: View {
    let store: DeckStore
    let deckID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechSynthesizer()
    @State private var index = 0

    private var deck: WordDeck? { store.deck(id: deckID) }
    private var words: [DeckWord] { deck?.words ?? [] }

    var body: some View {
        ZStack {
            AppBackground()
            if words.isEmpty {
                empty
            } else {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    TabView(selection: $index) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { i, word in
                            ScrollView {
                                PreviewCard(word: word, position: i + 1,
                                            total: words.count, speech: speech)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.top, Theme.Spacing.sm)
                                    .padding(.bottom, Theme.Spacing.lg)
                            }
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    navButtons
                }
                .padding(.top, Theme.Spacing.sm)
            }
        }
    }

    // MARK: - Header (close + progress + counter)

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.bold)).foregroundStyle(.duoHare)
            }
            DuoProgressBar(value: Double(index + 1) / Double(max(1, words.count)))
            Text("\(index + 1) / \(words.count)")
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(.duoWolf)
                .contentTransition(.numericText())
                .animation(.snappy, value: index)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Prev / Next

    private var navButtons: some View {
        let isLast = index >= words.count - 1
        return HStack(spacing: Theme.Spacing.sm) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    index = max(0, index - 1)
                }
            } label: {
                Label("Trước", systemImage: "chevron.left")
            }
            .buttonStyle(DuoButtonStyle(color: .duoPolar, edge: .duoSwan,
                                        foreground: .duoWolf, enabled: index > 0))
            .disabled(index == 0)

            Button {
                if isLast { dismiss() }
                else { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { index += 1 } }
            } label: {
                Label(isLast ? "Xong" : "Tiếp",
                      systemImage: isLast ? "checkmark" : "chevron.right")
            }
            .buttonStyle(.duoPrimary(enabled: true))
            .keyboardShortcut(.defaultAction)   // Return advances
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Chưa có từ nào", systemImage: "tray")
        } description: {
            Text("Thêm từ vào khóa học này để xem trước.")
        } actions: {
            Button("Đóng") { dismiss() }
        }
    }
}

// MARK: - One word, full definition

private struct PreviewCard: View {
    let word: DeckWord
    let position: Int
    let total: Int
    let speech: SpeechSynthesizer

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Text("TỪ \(position)/\(total)")
                    .font(.subheadline.weight(.heavy)).foregroundStyle(.duoGold)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.duoGold.opacity(0.18)))
                Spacer()
                GrowthBadge(progress: word.correctCount)
                    .scaleEffect(0.7).frame(width: 40, height: 46)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Text(word.word)
                    .font(.system(size: 34, weight: .heavy)).foregroundStyle(.duoInk)
                    .multilineTextAlignment(.center)
                Button { speech.speak(word.word, id: word.id.uuidString) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title2).foregroundStyle(.duoBlue)
                }
                .buttonStyle(.plain)
            }

            if let pos = word.partOfSpeech, !pos.isEmpty {
                Text(pos)
                    .font(.caption.weight(.heavy)).foregroundStyle(.duoIndigo)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.duoIndigo.opacity(0.15)))
            }
            if !word.pronunciation.isEmpty {
                Text(word.pronunciation).font(.title3.weight(.medium)).foregroundStyle(.duoWolf)
            }

            Divider().overlay(Color.duoSwan).padding(.vertical, 2)

            Text(word.meaning)
                .font(.title3.weight(.bold)).foregroundStyle(.duoInk)
                .multilineTextAlignment(.center)
            if !word.example.isEmpty {
                Text("“\(word.example)”")
                    .font(.callout.italic()).foregroundStyle(.duoWolf)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .duoCard()
    }
}

#Preview {
    DeckPreviewView(store: DeckStore(), deckID: WordDeck.sample.id)
}
