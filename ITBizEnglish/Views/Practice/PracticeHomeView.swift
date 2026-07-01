//
//  PracticeHomeView.swift
//  ITBizEnglish
//
//  Self-Translate home: a list of sentence sets. Each set holds Vietnamese
//  sentences the user wants to be able to say; they write the English and
//  Gemini grades it.
//

import SwiftUI

struct PracticeHomeView: View {
    @Bindable var store: PracticeStore
    var decks: DeckStore
    @State private var showNewSet = false
    @State private var newTitle = ""

    var body: some View {
        ZStack {
            AppBackground()
            if store.sets.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    AnimatedGIF(name: "waiting5").frame(width: 150, height: 150)
                    VStack(spacing: 6) {
                        Text("Chưa có bộ câu nào").font(.title2.weight(.heavy)).foregroundStyle(.duoInk)
                        Text("Tạo một bộ, thêm câu tiếng Việt bạn muốn nói, rồi tự viết tiếng Anh.")
                            .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                            .multilineTextAlignment(.center)
                    }
                    Button("Tạo bộ mới") { showNewSet = true }
                        .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge))
                        .frame(maxWidth: 260)
                }
                .padding(Theme.Spacing.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(store.sets) { set in
                            NavigationLink {
                                PracticeSetView(store: store, setID: set.id, decks: decks)
                            } label: {
                                SetRow(set: set)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation { store.deleteSet(id: set.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .navigationTitle("Self-Translate")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewSet = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New set", isPresented: $showNewSet) {
            TextField("Set title", text: $newTitle)
            Button("Create") {
                let t = newTitle.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.createSet(title: t) }
                newTitle = ""
            }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
    }
}

private struct SetRow: View {
    let set: PracticeSet
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(set.accent).frame(width: 52, height: 52)
                Image(systemName: set.icon).foregroundStyle(.white).font(.title3)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(set.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                Text("\(set.checkedCount)/\(set.total) practiced")
                    .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                DuoProgressBar(value: set.progress, tint: set.accent, height: 10)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.duoSwan)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

#Preview {
    NavigationStack { PracticeHomeView(store: PracticeStore(), decks: DeckStore()) }
}
