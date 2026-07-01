//
//  PracticeWriteView.swift
//  ITBizEnglish
//
//  The heart of Self-Translate: show a Vietnamese sentence, the user writes the
//  English, and Gemini grades it — score, verdict, an improved version, and
//  specific notes on what to fix. The reference answer is hidden by default
//  (only a hint). Feedback is cached on the sentence for reuse.
//

import SwiftUI
struct PracticeWriteView: View {
    @Bindable var store: PracticeStore
    let setID: UUID
    let sentenceID: UUID
    var decks: DeckStore
    /// Ordered sentence IDs this practice run walks through. Empty = the whole
    /// set (used by "review difficult only" to limit the run to flagged ones).
    var queue: [UUID] = []
    /// Move to the next sentence, or `nil` to return to the set's list.
    let onNext: (UUID?) -> Void

    /// Drives the "save words to a deck" sheet.
    @State private var saveWordsSource: SaveWordsSource?

    @State private var attempt = ""
    @State private var isChecking = false
    @State private var feedback: AIFeedback?
    @State private var error: String?
    @State private var showReference = false
    @State private var speech = SpeechSynthesizer()
    @FocusState private var typing: Bool

    // Word-bank ("Ghép từ") mode
    private enum WriteMode { case write, wordBank }
    @State private var mode: WriteMode = .write

    private var sentence: PracticeSentence? {
        store.set(id: setID)?.sentences.first { $0.id == sentenceID }
    }

    /// The order to walk: the explicit `queue` if given, else the full set.
    private var walkOrder: [UUID] {
        queue.isEmpty ? (store.set(id: setID)?.sentences.map(\.id) ?? []) : queue
    }

    private var nextSentenceID: UUID? {
        let order = walkOrder
        guard let idx = order.firstIndex(of: sentenceID), idx + 1 < order.count else { return nil }
        return order[idx + 1]
    }


    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if let s = sentence {
                        if hasReference(s) { modePicker(s) }
                        switch mode {
                        case .write:
                            promptCard(s)
                            answerEditor
                            checkButton
                            if let feedback { feedbackCard(feedback, sentence: s) }
                        case .wordBank:
                            wordBankSection(s)
                        }
                        referenceSection(s)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Write it in English")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { onNext(nil) } label: {
                    Label("List", systemImage: "list.bullet")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let s = sentence {
                    Button {
                        Haptics.tap()
                        store.toggleDifficult(forSentence: sentenceID, inSet: setID)
                    } label: {
                        Label(s.isDifficult ? "Bỏ đánh dấu khó" : "Đánh dấu câu khó",
                              systemImage: s.isDifficult ? "flag.fill" : "flag")
                            .foregroundStyle(s.isDifficult ? .duoRed : .duoWolf)
                    }
                }
            }
        }
        .onAppear(perform: loadCached)
        .sheet(item: $saveWordsSource) { source in
            SaveWordsSheet(decks: decks, text: source.text)
        }
    }

    /// Small "Lưu từ" button that opens the word-picker sheet for `text`.
    private func saveWordsButton(_ text: String) -> some View {
        Button {
            saveWordsSource = SaveWordsSource(text: text)
        } label: {
            Label("Lưu từ", systemImage: "text.badge.plus")
                .font(.caption.weight(.heavy))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.duoBlue)
    }

    // MARK: - Mode picker

    private func hasReference(_ s: PracticeSentence) -> Bool {
        !s.referenceEnglish.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func modePicker(_ s: PracticeSentence) -> some View {
        Picker("", selection: $mode) {
            Text("Tự viết").tag(WriteMode.write)
            Text("Ghép từ").tag(WriteMode.wordBank)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Word bank ("Ghép từ")

    private func wordBankSection(_ s: PracticeSentence) -> some View {
        WordBankView(
            vietnamese: s.vietnamese,
            target: s.referenceEnglish,
            distractors: distractors(for: s),
            speech: speech,
            onChecked: { ok, attempt in
                guard ok else { return }
                let fb = AIFeedback(score: 100, verdict: "Ghép đúng",
                                    correctedVersion: s.referenceEnglish, notes: [])
                store.saveFeedback(fb, attempt: attempt, forSentence: s.id, inSet: setID)
            }
        ) {
            if let nextID = nextSentenceID {
                Button("Tiếp tục") { onNext(nextID) }.buttonStyle(.brand)
            } else {
                Button("Done") { onNext(nil) }.buttonStyle(.brand)
            }
        }
    }

    /// A few distractor words pulled from other sentences in the same set.
    private func distractors(for s: PracticeSentence) -> [String] {
        guard let set = store.set(id: setID) else { return [] }
        var pool = Set<String>()
        for other in set.sentences where other.id != s.id {
            for w in other.referenceEnglish.split(separator: " ") { pool.insert(String(w)) }
        }
        let target = Set(s.referenceEnglish.split(separator: " ").map(String.init))
        return Array(pool.subtracting(target).shuffled().prefix(3))
    }

    // MARK: - Prompt

    private func promptCard(_ s: PracticeSentence) -> some View {
        GroupBox {
            Text(s.vietnamese)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.duoInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Vietnamese", systemImage: "character.bubble")
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoWolf)
        }
        .groupBoxStyle(.card)
    }

    private var answerEditor: some View {
        GroupBox {
            TextField("Type your English…", text: $attempt, axis: .vertical)
                .lineLimit(2...6).focused($typing).font(.body)
        } label: {
            Label("Your English", systemImage: "pencil")
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoWolf)
        }
        .groupBoxStyle(.card)
    }

    private var checkButton: some View {
        Button(action: check) {
            HStack(spacing: Theme.Spacing.sm) {
                if isChecking { ProgressView().tint(.white); Text("Checking…") }
                else { Image(systemName: "checkmark.seal"); Text("Check with AI") }
            }
        }
        .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge, enabled: canCheck))
        .disabled(!canCheck)
        .keyboardShortcut(.return, modifiers: .command)   // ⌘+Return submits (field is multi-line)
        .overlay(alignment: .bottom) {
            if let error {
                Text(error).font(.caption.weight(.bold)).foregroundStyle(.duoRed)
                    .padding(.top, 4).offset(y: 22)
            }
        }
    }

    private var canCheck: Bool {
        !isChecking && !attempt.trimmingCharacters(in: .whitespaces).isEmpty && AppConfiguration.hasGeminiKey
    }

    // MARK: - Feedback

    private func feedbackCard(_ fb: AIFeedback, sentence s: PracticeSentence) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("\(fb.emoji) \(fb.verdict)").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
                Text("\(fb.score)/100").font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(fb.ratingColor)
            }
            DuoProgressBar(value: Double(fb.score) / 100, tint: fb.ratingColor, height: 12)

            if !fb.correctedVersion.isEmpty {
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SUGGESTED").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                        Text(fb.correctedVersion).font(.body.weight(.bold)).foregroundStyle(.duoInk).textSelection(.enabled)
                        saveWordsButton(fb.correctedVersion)
                    }
                    Spacer()
                    Button {
                        speech.speak(fb.correctedVersion, id: "fb-\(sentenceID)")
                    } label: { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.duoIndigo) }
                        .buttonStyle(.plain)
                }
            }

            if !fb.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("CẦN CHỈNH").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                    ForEach(fb.notes, id: \.self) { note in
                        Label(note, systemImage: "arrow.right.circle.fill")
                            .font(.callout.weight(.medium)).foregroundStyle(.duoInk)
                    }
                }
            } else {
                Label("Tuyệt vời, không có gì cần sửa!", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.bold)).foregroundStyle(.duoGreen)
            }
       Divider()
            if let nextID = nextSentenceID {
                Button(action: { onNext(nextID) }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Next sentence")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge))
                .keyboardShortcut(.defaultAction)   // Return → next sentence
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("✅ Hoàn thành tất cả câu!").font(.headline.weight(.heavy)).foregroundStyle(.duoGreen)
                    Button("Done") { onNext(nil) }
                        .buttonStyle(.duoGreen)
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func referenceSection(_ s: PracticeSentence) -> some View {
        if !s.referenceEnglish.isEmpty {
            DisclosureGroup(isExpanded: $showReference) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.referenceEnglish)
                        .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    saveWordsButton(s.referenceEnglish)
                }
                .padding(.top, 6)
            } label: {
                Label("Reference (chỉ để tham khảo)", systemImage: "eye")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.duoWolf)
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.duoPolar))
        }
    }

    // MARK: - Logic

    private func loadCached() {
        guard let s = sentence else { return }
        if attempt.isEmpty { attempt = s.lastAttempt }
        if feedback == nil { feedback = s.feedback }
    }

    private func check() {
        guard let s = sentence else { return }
        typing = false
        error = nil
        isChecking = true
        let text = attempt
        Task {
            do {
                let fb = try await SentenceCheckService().check(
                    vietnamese: s.vietnamese, attempt: text, reference: s.referenceEnglish)
                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { feedback = fb }
                    store.saveFeedback(fb, attempt: text, forSentence: sentenceID, inSet: setID)
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isChecking = false
                }
            }
        }
    }
}
