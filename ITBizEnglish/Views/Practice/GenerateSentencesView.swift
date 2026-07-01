//
//  GenerateSentencesView.swift
//  ITBizEnglish
//
//  AI sentence generator for Self-Translate. The user picks a topic and how
//  many sentences to generate; Gemini returns Vietnamese sentences (+ an
//  English reference hint). Everything lands in a review list FIRST — the user
//  can deselect or delete any sentence — and only the kept ones get imported.
//

import SwiftUI

struct GenerateSentencesView: View {
    @Bindable var store: PracticeStore
    let setID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var topic: String
    @State private var count: Int = 10

    @State private var isGenerating = false
    @State private var error: String?

    /// Generated candidates awaiting the user's review.
    @State private var candidates: [Candidate] = []

    init(store: PracticeStore, setID: UUID, defaultTopic: String = "") {
        self.store = store
        self.setID = setID
        _topic = State(initialValue: defaultTopic)
    }

    /// A generated sentence the user can toggle/keep before import.
    private struct Candidate: Identifiable {
        let id = UUID()
        var vietnamese: String
        var english: String
        var include: Bool = true
    }

    private var selectedCount: Int { candidates.filter(\.include).count }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if candidates.isEmpty {
                    setupForm
                } else {
                    reviewList
                }
            }
            .navigationTitle(candidates.isEmpty ? "Tạo câu" : "Duyệt (\(selectedCount))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func fieldCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    // MARK: - Setup form

    private var setupForm: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                fieldCard("CHỦ ĐỀ / NGỮ CẢNH") {
                    TextField("vd: daily standup, code review…", text: $topic, axis: .vertical)
                        .lineLimit(1...3).font(.body.weight(.medium)).foregroundStyle(.duoInk)
                }

                fieldCard("SỐ CÂU") {
                    Stepper(value: $count, in: 1...30) {
                        Text("\(count) câu").font(.body.weight(.heavy)).foregroundStyle(.duoInk)
                    }
                    .tint(.duoIndigo)
                    HStack(spacing: 8) {
                        ForEach([5, 10, 15, 20], id: \.self) { n in
                            Button("\(n)") { count = n }
                                .font(.callout.weight(.heavy))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(count == n ? Color.duoIndigo.opacity(0.18) : Color.duoPolar))
                                .foregroundStyle(count == n ? .duoIndigo : .duoWolf)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text(AppConfiguration.hasGeminiKey
                     ? "Câu AI tạo sẽ vào danh sách duyệt — bạn chọn trước khi nhập."
                     : "⚠️ Thêm Gemini key trong Cài đặt để tạo câu.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.bold)).foregroundStyle(.duoRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: generate) {
                    HStack(spacing: 8) {
                        if isGenerating { ProgressView().controlSize(.small).tint(.white) }
                        Label(isGenerating ? "Đang tạo…" : "Tạo bằng AI", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge,
                                  enabled: AppConfiguration.hasGeminiKey && !isGenerating))
                .disabled(isGenerating || !AppConfiguration.hasGeminiKey)
            }
            .padding(Theme.Spacing.md)
        }
    }

    // MARK: - Review list

    private var reviewList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                HStack {
                    Button(selectedCount == candidates.count ? "Bỏ chọn tất cả" : "Chọn tất cả") {
                        let selectAll = selectedCount != candidates.count
                        for i in candidates.indices { candidates[i].include = selectAll }
                    }
                    .font(.subheadline.weight(.heavy)).foregroundStyle(.duoIndigo)
                    Spacer()
                    Button { candidates = []; error = nil } label: {
                        Label("Tạo lại", systemImage: "arrow.clockwise").font(.subheadline.weight(.heavy))
                    }
                    .foregroundStyle(.duoWolf)
                }

                ForEach($candidates) { $c in
                    Button { c.include.toggle() } label: { candidateCard(c) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                candidates.removeAll { $0.id == c.id }
                            } label: { Label("Xóa", systemImage: "trash") }
                        }
                }

                Button("Nhập \(selectedCount) câu") { importSelected() }
                    .buttonStyle(.duoPrimary(enabled: selectedCount > 0))
                    .disabled(selectedCount == 0)
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func candidateCard(_ c: Candidate) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: c.include ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(c.include ? .duoIndigo : .duoSwan)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.vietnamese).font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk)
                if !c.english.isEmpty {
                    Text(c.english).font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(c.include ? Color.duoIndigo : Color.duoSwan, lineWidth: 2))
    }

    // MARK: - Actions

    private func generate() {
        error = nil
        isGenerating = true
        let topicSnapshot = topic
        let countSnapshot = count
        Task {
            do {
                let result = try await PracticeAIService()
                    .generateSentences(topic: topicSnapshot, count: countSnapshot)
                await MainActor.run {
                    candidates = result.map {
                        Candidate(vietnamese: $0.vietnamese, english: $0.referenceEnglish)
                    }
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func importSelected() {
        let sentences = candidates
            .filter(\.include)
            .map { PracticeSentence(vietnamese: $0.vietnamese, referenceEnglish: $0.english) }
        store.addSentences(sentences, toSet: setID)
        dismiss()
    }
}
