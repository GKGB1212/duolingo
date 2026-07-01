//
//  ChatHistoryView.swift
//  ITBizEnglish
//
//  Looks back over finished "Chat with AI" conversations. The list shows each
//  archived session (newest first) with its topic, date and score; tapping one
//  opens the full transcript plus the AI's review, and lets the user save
//  vocabulary from it.
//

import SwiftUI

struct ChatHistoryView: View {
    @Bindable var history: ChatHistoryStore
    var decks: DeckStore

    @State private var confirmClear = false

    var body: some View {
        ZStack {
            AppBackground()
            if history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        ForEach(history.entries) { entry in
                            NavigationLink {
                                ChatHistoryDetailView(entry: entry, decks: decks)
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation { history.delete(id: entry.id) }
                                } label: {
                                    Label("Xoá", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .navigationTitle("Lịch sử Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .alert("Xoá toàn bộ lịch sử?", isPresented: $confirmClear) {
            Button("Xoá hết", role: .destructive) { withAnimation { history.clear() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Không thể hoàn tác.")
        }
    }

    private func row(_ e: ChatHistoryEntry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(e.color).frame(width: 50, height: 50)
                Image(systemName: e.topicIcon).foregroundStyle(.white).font(.title3.weight(.bold))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.topicTitle).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                Text("\(e.date.formatted(date: .abbreviated, time: .shortened)) · \(e.level.label)")
                    .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
            }
            Spacer(minLength: 0)
            Text("\(e.review.score)")
                .font(.headline.weight(.heavy).monospacedDigit()).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(e.review.ratingColor))
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 54, weight: .bold)).foregroundStyle(.duoHare)
            Text("Chưa có hội thoại nào").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Hoàn thành một buổi Chat rồi nhấn “Kết thúc” — buổi đó sẽ được lưu vào đây để xem lại.")
                .font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
    }
}

// MARK: - Detail (transcript + review)

struct ChatHistoryDetailView: View {
    let entry: ChatHistoryEntry
    var decks: DeckStore

    @State private var speech = SpeechSynthesizer()
    @State private var showSaveWords = false

    /// Every line joined, so the user can pick vocabulary from the whole chat.
    private var transcriptText: String {
        entry.messages.map(\.text).joined(separator: " ")
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    scoreCard
                    transcriptCard
                    Button { showSaveWords = true } label: {
                        Label("Lưu từ vựng đã học", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge))
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle(entry.topicTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showSaveWords) {
            SaveWordsSheet(decks: decks, text: transcriptText)
        }
    }

    private var scoreCard: some View {
        let r = entry.review
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("\(r.emoji) \(r.verdict)").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
                Text("\(r.score)/100")
                    .font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(r.ratingColor)
            }
            DuoProgressBar(value: Double(r.score) / 100, tint: r.ratingColor, height: 12)

            if !r.strengths.isEmpty {
                Divider()
                Text("LÀM TỐT").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                ForEach(r.strengths, id: \.self) { s in
                    Label(s, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.duoInk)
                }
            }
            if !r.improvements.isEmpty {
                Divider()
                Text("CẦN CẢI THIỆN").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                ForEach(r.improvements, id: \.self) { s in
                    Label(s, systemImage: "arrow.up.forward.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.duoInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("HỘI THOẠI").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
            ForEach(entry.messages) { messageRow($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    @ViewBuilder
    private func messageRow(_ m: ChatMessage) -> some View {
        let isUser = m.role == .user
        HStack {
            if isUser { Spacer(minLength: 28) }
            VStack(alignment: .leading, spacing: 5) {
                Text(m.text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isUser ? .white : .duoInk)
                if !isUser, let vi = m.translation, !vi.isEmpty {
                    Text(vi).font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                }
                if !isUser {
                    Button { speech.speak(m.text, id: m.id.uuidString) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.footnote.weight(.bold)).foregroundStyle(entry.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isUser ? AnyShapeStyle(entry.color) : AnyShapeStyle(Color.duoPolar)))
            if !isUser { Spacer(minLength: 28) }
        }
    }
}
