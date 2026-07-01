//
//  TranslationView.swift
//  ITBizEnglish
//
//  The Sentence Translator screen — Vietnamese in, casual + professional
//  English out, with copy / save / listen actions and generated tags.
//

import SwiftUI

struct TranslationView: View {
    @State private var viewModel: TranslationViewModel
    @State private var speech = SpeechSynthesizer()
    @State private var settings = AppSettings.shared
    @FocusState private var inputFocused: Bool

    private let store: FlashcardStore
    private let decks: DeckStore

    /// Drives the "save words to a deck" sheet (carries the source English text).
    @State private var saveWordsSource: SaveWordsSource?
    /// Drives the "Ghép từ" word-bank practice sheet.
    @State private var practiceSource: WordBankPracticeSource?
    /// Drives the history push (a plain Button is used instead of a toolbar
    /// NavigationLink, which re-asserts itself on re-render).
    @State private var showHistory = false

    init(store: FlashcardStore, practice: PracticeStore, decks: DeckStore) {
        self.store = store
        self.decks = decks
        _viewModel = State(initialValue: TranslationViewModel(store: store, practice: practice))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    inputSection
                    resultSection
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Translator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            HistoryView(store: store) { result in
                viewModel.restore(result)
            }
        }
        .onChange(of: speech.speakingID) { _, _ in }
        .sheet(item: $saveWordsSource) { source in
            SaveWordsSheet(decks: decks, text: source.text)
        }
        .sheet(item: $practiceSource) { source in
            WordBankPracticeSheet(vietnamese: source.vietnamese,
                                  target: source.target,
                                  distractors: source.distractors)
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                editor
                charCounter
                actionRow
                aiStatusCaption
            }
        } label: {
            Label("Vietnamese", systemImage: "character.bubble")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.duoWolf)
        }
        .groupBoxStyle(.card)
    }

    @ViewBuilder
    private var aiStatusCaption: some View {
        if viewModel.isUsingRealAI {
            Label(settings.lastUsedSummary ?? "Sẵn sàng dịch bằng AI", systemImage: "sparkles")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.duoWolf)
        } else {
            Label("Demo mode — add your free key in Configuration.plist",
                  systemImage: "exclamationmark.circle")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.duoGoldEdge)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.inputText.isEmpty {
                Text("Nhập câu tiếng Việt cần dịch…")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.inputText)
                .frame(minHeight: 90, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .focused($inputFocused)
                .font(.body)
        }
    }

    private var charCounter: some View {
        HStack {
            if !viewModel.inputText.isEmpty {
                Button {
                    withAnimation { viewModel.clear() }
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.duoWolf)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(viewModel.inputText.count)/\(viewModel.characterLimit)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(viewModel.isOverLimit ? .duoRed : .duoWolf)
        }
    }

    private var actionRow: some View {
        Button(action: translate) {
            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Translating…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Translate")
                }
            }
        }
        .buttonStyle(.duoPrimary(enabled: viewModel.canTranslate))
        .disabled(!viewModel.canTranslate)
        .keyboardShortcut(.return, modifiers: .command)   // ⌘+Return translates (input is multi-line)
        .sensoryFeedback(.impact, trigger: viewModel.isLoading) { _, now in now }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        if let error = viewModel.errorMessage {
            errorCard(error)
        }

        if viewModel.isLoading && viewModel.translationResult == nil {
            loadingPlaceholder
        }

        // Nothing typed yet → offer tappable starter sentences to practice with.
        if viewModel.translationResult == nil, !viewModel.isLoading,
           viewModel.errorMessage == nil,
           viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestionsSection
        }

        if let result = viewModel.translationResult {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(Tone.allCases) { tone in
                    OptionCard(
                        tone: tone,
                        text: tone.text(from: result.englishOptions),
                        isSaved: viewModel.isSaved(tone: tone),
                        isSpeaking: speech.speakingID == cardID(result, tone),
                        onCopy: { copy(tone.text(from: result.englishOptions)) },
                        onSave: { withAnimation { viewModel.toggleSave(tone: tone) } },
                        onSpeak: { speech.speak(tone.text(from: result.englishOptions),
                                                id: cardID(result, tone)) },
                        onSaveWords: { saveWordsSource = SaveWordsSource(text: tone.text(from: result.englishOptions)) },
                        onPractice: { startPractice(result, tone) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !result.tags.isEmpty {
                    tagsCard(result.tags)
                }
            }
        }
    }

    // MARK: - Quick-start suggestions

    /// Common IT / business Vietnamese lines the user can tap to translate
    /// instantly — fills the empty state and nudges them to practice more.
    private static let suggestions = [
        "Mình sẽ hoàn thành task này trước cuối ngày.",
        "Cho mình xin thêm thời gian để review nhé.",
        "Mình đang bị block ở phần tích hợp API.",
        "Bạn có thể giải thích lại yêu cầu này không?",
        "Mình nghĩ nên tạo một cuộc họp để thống nhất.",
        "Phần này để qua sprint sau làm được không?"
    ]

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Thử dịch nhanh", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoWolf)
                .padding(.leading, 4)
            ForEach(Self.suggestions, id: \.self) { line in
                Button { pickSuggestion(line) } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "text.bubble.fill")
                            .font(.callout).foregroundStyle(.brand)
                        Text(line)
                            .font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                    }
                    .padding(Theme.Spacing.md)
                    .duoCard(cornerRadius: Theme.Radius.card)
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }

    private func pickSuggestion(_ line: String) {
        viewModel.inputText = line
        translate()
    }

    private func tagsCard(_ tags: [String]) -> some View {
        GroupBox {
            TagFlow(tags: tags, color: .duoBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Tags", systemImage: "tag")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.duoWolf)
        }
        .groupBoxStyle(.card)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.duoPolar)
                    .frame(height: 120)
                    .shimmer()
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.duoRed)
            Text(message)
                .font(.callout.weight(.bold))
                .foregroundStyle(.duoWrongText)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.duoWrongFill)
        )
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Helpers

    private func cardID(_ result: TranslationResult, _ tone: Tone) -> String {
        result.id + "-" + tone.rawValue
    }

    private func translate() {
        inputFocused = false
        viewModel.translate()
    }

    /// Opens the "Ghép từ" practice for one tone — the user rebuilds that
    /// English sentence, with the *other* tone's words mixed in as distractors.
    private func startPractice(_ result: TranslationResult, _ tone: Tone) {
        let target = tone.text(from: result.englishOptions)
        let other = Tone.allCases.first { $0 != tone }
            .map { $0.text(from: result.englishOptions) } ?? ""
        practiceSource = WordBankPracticeSource(
            vietnamese: result.vietnameseText,
            target: target,
            distractors: other.split(separator: " ").map(String.init)
        )
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

// MARK: - GroupBox style

struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            configuration.label
            configuration.content
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

extension GroupBoxStyle where Self == CardGroupBoxStyle {
    static var card: CardGroupBoxStyle { CardGroupBoxStyle() }
}

// MARK: - Save words to a deck

/// Identifiable wrapper so the source English text can drive a `.sheet(item:)`.
struct SaveWordsSource: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Word-bank practice

/// Carries everything the "Ghép từ" practice sheet needs.
struct WordBankPracticeSource: Identifiable {
    let id = UUID()
    let vietnamese: String
    let target: String
    let distractors: [String]
}

/// Presents the shared `WordBankView` as a sheet from the Translator.
struct WordBankPracticeSheet: View {
    let vietnamese: String
    let target: String
    let distractors: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechSynthesizer()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    WordBankView(vietnamese: vietnamese,
                                 target: target,
                                 distractors: distractors,
                                 speech: speech) {
                        Button("Xong") { dismiss() }.buttonStyle(.brand)
                    }
                    .padding(Theme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Ghép từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

/// Lets the user pick individual words from a translation and save them as
/// vocabulary into a deck — AI fills in meaning / IPA / example automatically.
struct SaveWordsSheet: View {
    @Bindable var decks: DeckStore
    let text: String
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String> = []
    @State private var selectedDeckID: UUID?
    @State private var newDeckTitle = ""
    @State private var isWorking = false
    @State private var error: String?

    /// Unique words from the source text (dedup case-insensitively). Letters,
    /// apostrophes and hyphens stay together so a hyphenated compound like
    /// "two-factor" or "well-known" is one saveable chip — not split apart.
    private var words: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }) {
            // Drop any leading/trailing hyphen or apostrophe (e.g. an em-dash run).
            let w = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
            let key = w.lowercased()
            if w.count > 1, !seen.contains(key) { seen.insert(key); result.append(w) }
        }
        return result
    }

    private var destinationDeckID: UUID? { selectedDeckID }

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Picker("Deck", selection: $selectedDeckID) {
                        Text("➕ New deck").tag(UUID?.none)
                        ForEach(decks.decks) { deck in
                            Text(deck.title).tag(UUID?.some(deck.id))
                        }
                    }
                    if destinationDeckID == nil {
                        TextField("New deck title", text: $newDeckTitle)
                    }
                }

                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(words, id: \.self) { word in
                            wordChip(word)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Tap words to save (\(selected.count) selected)")
                } footer: {
                    Text(AppConfiguration.hasGeminiKey
                         ? "AI will fill in the Vietnamese meaning, pronunciation and an example for each word."
                         : "⚠️ Add a Gemini key in Configuration.plist to save words.")
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.bold)).foregroundStyle(.duoRed)
                }
            }
            .navigationTitle("Save Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isWorking { ProgressView() } else { Text("Save \(selected.count)") }
                    }
                    .disabled(isWorking || selected.isEmpty || !AppConfiguration.hasGeminiKey)
                }
            }
        }
    }

    private func wordChip(_ word: String) -> some View {
        let isOn = selected.contains(word)
        return Button {
            if isOn { selected.remove(word) } else { selected.insert(word) }
        } label: {
            Text(word)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? .white : .duoInk)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(isOn ? AnyShapeStyle(.duoBlue) : AnyShapeStyle(Color.duoPolar)))
                .overlay(Capsule().strokeBorder(isOn ? Color.duoBlue : Color.duoSwan, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        error = nil
        isWorking = true
        let terms = Array(selected).joined(separator: "\n")
        Task {
            do {
                let generated = try await DeckAIService().generateWords(from: terms)
                // Use the current sentence as each word's example.
                let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let words = generated.map { word -> DeckWord in
                    var w = word
                    if !sentence.isEmpty { w.example = sentence }
                    return w
                }
                await MainActor.run {
                    let id = ensureDeckID()
                    decks.addWords(words, toDeck: id)
                    isWorking = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isWorking = false
                }
            }
        }
    }

    private func ensureDeckID() -> UUID {
        if let id = destinationDeckID, decks.deck(id: id) != nil { return id }
        let title = newDeckTitle.trimmingCharacters(in: .whitespaces)
        return decks.createDeck(title: title.isEmpty ? "Saved Words" : title).id
    }
}

#Preview {
    NavigationStack {
        TranslationView(store: FlashcardStore(), practice: PracticeStore(), decks: DeckStore())
    }
}
