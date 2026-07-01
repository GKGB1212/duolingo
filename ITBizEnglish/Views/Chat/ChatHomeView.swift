//
//  ChatHomeView.swift
//  ITBizEnglish
//
//  "Chat with AI" home: pick a workplace scenario, then practice a spoken-English
//  conversation. Tapping a topic opens an immersive full-screen chat session.
//

import SwiftUI

struct ChatHomeView: View {
    var decks: DeckStore
    @Bindable var history: ChatHistoryStore

    @State private var activeTopic: ChatTopic?
    @State private var level: ChatLevel = .medium
    @State private var mascot = AnimatedGIF.randomWaiting()
    /// Drives the history push (a plain Button is used instead of a toolbar
    /// NavigationLink, which re-asserts itself on re-render).
    @State private var showHistory = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    intro
                    levelCard
                    HStack {
                        Text("CHỌN CHỦ ĐỀ").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                        Spacer()
                    }
                    .padding(.top, Theme.Spacing.xs)

                    ForEach(ChatTopic.all) { topic in
                        Button { activeTopic = topic } label: { topicRow(topic) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Chat cùng AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            ChatHistoryView(history: history, decks: decks)
        }
        .fullScreenCover(item: $activeTopic) { topic in
            ChatSessionView(topic: topic, level: level, decks: decks, history: history)
        }
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("CẤP ĐỘ").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(ChatLevel.allCases) { lv in
                    let on = level == lv
                    Button {
                        withAnimation(.snappy) { level = lv }
                    } label: {
                        Text(lv.label)
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(on ? .white : .duoInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? AnyShapeStyle(lv.color) : AnyShapeStyle(Color.duoPolar)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(on ? lv.color : Color.duoSwan, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var intro: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AnimatedGIF(name: mascot).frame(width: 86, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("Luyện nói tiếng Anh công việc")
                    .font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Text("Chọn một tình huống, trò chuyện với AI, theo dõi tiến độ rồi nhận nhận xét cuối buổi.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func topicRow(_ topic: ChatTopic) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(topic.color).frame(width: 52, height: 52)
                Image(systemName: topic.icon).foregroundStyle(.white).font(.title3.weight(.bold))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                Text(topic.subtitle).font(.caption.weight(.bold)).foregroundStyle(.duoWolf).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.footnote.weight(.bold)).foregroundStyle(topic.color)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}
