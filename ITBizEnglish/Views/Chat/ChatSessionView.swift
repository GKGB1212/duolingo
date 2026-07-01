//
//  ChatSessionView.swift
//  ITBizEnglish
//
//  The immersive AI work-chat: a Duolingo-style conversation with a progress bar
//  toward the scenario goal, an animated "typing…" indicator while the AI replies,
//  and — when the user ends — an AI review plus the option to save vocabulary
//  (from both sides of the chat) into a deck.
//

import SwiftUI

struct ChatSessionView: View {
    let topic: ChatTopic
    var level: ChatLevel = .medium
    var decks: DeckStore
    var history: ChatHistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isSending = false        // AI is composing a reply
    @State private var progress = 0
    @State private var error: String?
    @State private var started = false
    @State private var mascot = AnimatedGIF.randomWaiting()
    @State private var translated: Set<UUID> = []   // AI lines showing Vietnamese
    @FocusState private var inputFocused: Bool
    @State private var speech = SpeechSynthesizer()

    // Suggested replies for the user (from the latest AI turn) + an in-chat toggle.
    @State private var suggestions: [String] = []
    @AppStorage("itbiz.chat.showSuggestions") private var showSuggestions = true

    // Ending → review
    @State private var isEnding = false          // grading in progress
    @State private var review: ChatReview?
    @State private var endError: String?
    @State private var confirmExit = false

    private var canEnd: Bool { messages.contains { $0.role == .user } }
    private var canSend: Bool { !isSending && !input.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            AppBackground()
            if let review {
                ChatReviewView(topic: topic, mascot: mascot, messages: messages, review: review,
                               decks: decks, onClose: { dismiss() })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                chatBody
            }
            if isEnding { endingOverlay }
        }
        // The Chat session is a full-screen cover, so it sits above RootView's
        // bubble — give it its own so quick lookup stays reachable mid-chat.
        .overlay {
            if review == nil, AppSettings.shared.lookupBubbleEnabled {
                QuickLookupBubble(decks: decks)
            }
        }
        .onAppear { startIfNeeded() }
        .alert("Thoát hội thoại?", isPresented: $confirmExit) {
            Button("Thoát", role: .destructive) { dismiss() }
            Button("Ở lại", role: .cancel) {}
        } message: {
            Text("Cuộc trò chuyện này sẽ không được lưu.")
        }
        .alert("Không chấm được", isPresented: .constant(endError != nil)) {
            Button("Thử lại") { endError = nil; endConversation() }
            Button("Đóng", role: .cancel) { endError = nil }
        } message: {
            Text(endError ?? "")
        }
    }

    // MARK: - Chat

    private var chatBody: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(messages) { bubble($0).id($0.id) }
                        if isSending { typingRow }
                        if let error { errorRow(error) }
                        if progress >= 100 { completedBanner }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(Theme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in scrollDown(proxy) }
                .onChange(of: isSending) { _, _ in scrollDown(proxy) }
            }
            suggestionsStrip
            inputBar
        }
    }

    /// One compact, horizontally-scrolling row of suggested replies, shown just
    /// above the input when the user has suggestions turned on.
    @ViewBuilder
    private var suggestionsStrip: some View {
        if showSuggestions, !suggestions.isEmpty, review == nil, !isEnding {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(topic.color)
                    ForEach(suggestions, id: \.self) { s in
                        Button { useSuggestion(s) } label: {
                            Text(s)
                                .font(.footnote.weight(.semibold)).foregroundStyle(.duoInk)
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(topic.color.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(topic.color.opacity(0.45), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Put a suggestion into the input so the user can read / tweak it, then send.
    private func useSuggestion(_ text: String) {
        input = text
        inputFocused = true
        Haptics.tap()
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: Theme.Spacing.sm) {
                Button { canEnd ? (confirmExit = true) : dismiss() } label: {
                    Image(systemName: "xmark").font(.headline.weight(.bold)).foregroundStyle(.duoHare)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(topic.title).font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                    Text("\(progress)% hoàn thành").font(.caption2.weight(.bold)).foregroundStyle(topic.color)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { endConversation() } label: {
                    Text("Kết thúc").font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(canEnd ? AnyShapeStyle(topic.color) : AnyShapeStyle(Color.duoSwan)))
                }
                .disabled(!canEnd)
            }
            DuoProgressBar(value: Double(progress) / 100, tint: topic.color, height: 12)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.duoSwan).frame(height: 2) }
        )
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.role == .ai {
            HStack(alignment: .bottom, spacing: 8) {
                AnimatedGIF(name: mascot).frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.text)
                        .font(.callout.weight(.medium)).foregroundStyle(.duoInk)

                    if translated.contains(m.id), let vi = m.translation {
                        Divider()
                        Text(vi)
                            .font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf)
                            .transition(.opacity)
                    }

                    HStack(spacing: 10) {
                        Button { speech.speak(m.text, id: m.id.uuidString) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(topic.color)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(topic.color.opacity(0.14)))
                        }
                        .buttonStyle(.plain)

                        if m.translation != nil {
                            Button {
                                withAnimation(.snappy) {
                                    if translated.contains(m.id) { translated.remove(m.id) }
                                    else { translated.insert(m.id) }
                                }
                            } label: {
                                Label(translated.contains(m.id) ? "Ẩn tiếng Việt" : "Tiếng Việt",
                                      systemImage: "character.book.closed.fill")
                                    .font(.footnote.weight(.heavy))
                                    .foregroundStyle(topic.color)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(topic.color.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 1.5))
                Spacer(minLength: 28)
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            HStack(spacing: 8) {
                Spacer(minLength: 36)
                Text(m.text)
                    .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(topic.color))
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AnimatedGIF(name: mascot).frame(width: 38, height: 38)
            TypingDots()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 1.5))
            Spacer(minLength: 36)
        }
        .transition(.opacity)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.duoRed)
            Text(message).font(.caption.weight(.bold)).foregroundStyle(.duoWrongText)
            Spacer()
            Button("Thử lại") { respond() }.font(.caption.weight(.heavy)).tint(topic.color)
        }
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoWrongFill))
    }

    private var completedBanner: some View {
        VStack(spacing: 6) {
            Text("🎉 Bạn đã hoàn thành chủ đề!")
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Bấm “Kết thúc” để xem nhận xét, hoặc trò chuyện thêm.")
                .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(topic.color.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(topic.color.opacity(0.5), lineWidth: 2))
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                withAnimation(.snappy) { showSuggestions.toggle() }
                Haptics.tap()
            } label: {
                Image(systemName: showSuggestions ? "lightbulb.fill" : "lightbulb.slash")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(showSuggestions ? topic.color : .duoHare)
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)

            TextField("Nhập câu trả lời tiếng Anh…", text: $input, axis: .vertical)
                .lineLimit(1...4).font(.body).focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))

            Button(action: send) {
                Image(systemName: "arrow.up").font(.headline.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(canSend ? AnyShapeStyle(topic.color) : AnyShapeStyle(Color.duoSwan)))
            }
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)   // ⌘+Return sends (field is multi-line)
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .top) { Rectangle().fill(Color.duoSwan).frame(height: 2) }
        )
    }

    private var endingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                AnimatedGIF(name: "waiting2").frame(width: 120, height: 120)
                Text("Đang chấm điểm…").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                ProgressView().tint(topic.color)
            }
            .padding(Theme.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        }
        .transition(.opacity)
    }

    // MARK: - Logic

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        respond()   // AI opens the conversation
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        withAnimation { messages.append(ChatMessage(role: .user, text: text)) }
        input = ""
        withAnimation(.snappy) { suggestions = [] }   // stale until the next AI turn
        respond()
    }

    private func respond() {
        error = nil
        withAnimation { isSending = true }
        Task {
            do {
                let turn = try await ChatAIService().nextReply(topic: topic, level: level, history: messages)
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        messages.append(ChatMessage(role: .ai, text: turn.reply,
                                                    translation: turn.vi.isEmpty ? nil : turn.vi))
                        progress = max(progress, turn.progress)
                        suggestions = turn.suggestions
                        isSending = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    withAnimation { isSending = false }
                }
            }
        }
    }

    private func endConversation() {
        guard canEnd else { return }
        inputFocused = false
        withAnimation { isEnding = true }
        Task {
            do {
                let r = try await ChatAIService().review(topic: topic, level: level, history: messages)
                await MainActor.run {
                    SoundFX.completed()
                    // Archive the finished conversation so it can be reviewed later.
                    history.add(ChatHistoryEntry(topic: topic, level: level,
                                                 messages: messages, review: r))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        review = r; isEnding = false
                    }
                }
            } catch {
                await MainActor.run {
                    endError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    withAnimation { isEnding = false }
                }
            }
        }
    }
}

// MARK: - Animated typing dots ("…" bouncing)

struct TypingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.duoWolf)
                    .frame(width: 9, height: 9)
                    .offset(y: animating ? -5 : 4)
                    .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15), value: animating)
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Review + save vocabulary

private struct ChatReviewView: View {
    let topic: ChatTopic
    let mascot: String
    let messages: [ChatMessage]
    let review: ChatReview
    var decks: DeckStore
    let onClose: () -> Void

    @State private var showSaveWords = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                AnimatedGIF(name: review.didWell ? "happy" : "angry")
                    .frame(width: 170, height: 170)
                Text("Kết thúc hội thoại!")
                    .font(.title2.weight(.heavy)).foregroundStyle(.duoInk)

                scoreCard

                VStack(spacing: Theme.Spacing.sm) {
                    Button { showSaveWords = true } label: {
                        Label("Lưu từ vựng đã học", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge))

                    Button("Xong") { onClose() }
                        .buttonStyle(.brand)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(AppBackground())
        .sheet(isPresented: $showSaveWords) {
            ChatSaveWordsView(decks: decks, topic: topic, mascot: mascot, messages: messages)
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("\(review.emoji) \(review.verdict)")
                    .font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
                Text("\(review.score)/100")
                    .font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(review.ratingColor)
            }
            DuoProgressBar(value: Double(review.score) / 100, tint: review.ratingColor, height: 12)

            if !review.strengths.isEmpty {
                Divider()
                Text("LÀM TỐT").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                ForEach(review.strengths, id: \.self) { s in
                    Label(s, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.duoInk)
                }
            }
            if !review.improvements.isEmpty {
                Divider()
                Text("CẦN CẢI THIỆN").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                ForEach(review.improvements, id: \.self) { s in
                    Label(s, systemImage: "arrow.up.forward.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.duoInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

// MARK: - Save vocabulary, chat-style

/// Re-renders the whole conversation as chat bubbles whose words are tappable,
/// so the user picks vocabulary straight from the dialogue (both sides), then
/// saves the selection into a deck (AI fills in meaning / IPA / example).
private struct ChatSaveWordsView: View {
    var decks: DeckStore
    let topic: ChatTopic
    let mascot: String
    let messages: [ChatMessage]
    @Environment(\.dismiss) private var dismiss

    /// lowercased key → original-cased word, preserving what the user tapped.
    @State private var selected: [String: String] = [:]
    @State private var selectedDeckID: UUID?
    @State private var newDeckTitle = ""
    @State private var askNewDeck = false
    @State private var isWorking = false
    @State private var error: String?

    private var canSave: Bool { !selected.isEmpty && !isWorking && AppConfiguration.hasGeminiKey }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        Label("Chạm vào từ / cụm từ trong hội thoại để chọn lưu.",
                              systemImage: "hand.tap.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(messages) { selectableBubble($0) }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Chọn từ để lưu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .alert("Bộ từ mới", isPresented: $askNewDeck) {
                TextField("Tên bộ", text: $newDeckTitle)
                Button("OK") { selectedDeckID = nil }
                Button("Huỷ", role: .cancel) {}
            }
        }
    }

    // MARK: Bubbles — identical look to the chat, words are tappable

    @ViewBuilder
    private func selectableBubble(_ m: ChatMessage) -> some View {
        let isAI = m.role == .ai
        // Base / selected text colors per bubble so contrast holds either way.
        let base: Color = isAI ? .duoInk : .white
        let sel: Color  = isAI ? topic.color : .duoInk

        if isAI {
            HStack(alignment: .bottom, spacing: 8) {
                AnimatedGIF(name: mascot).frame(width: 38, height: 38)
                bubbleText(m.text, base: base, sel: sel)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.duoPolar))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 1.5))
                Spacer(minLength: 28)
            }
        } else {
            HStack(spacing: 8) {
                Spacer(minLength: 36)
                bubbleText(m.text, base: base, sel: sel)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(topic.color))
            }
        }
    }

    private func bubbleText(_ text: String, base: Color, sel: Color) -> some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(displayTokens(text).enumerated()), id: \.offset) { _, token in
                tokenView(token, base: base, sel: sel)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// One word: tappable when it cleans to a real word. Selecting only changes
    /// color + underline (same font weight) so the layout never shifts.
    @ViewBuilder
    private func tokenView(_ token: String, base: Color, sel: Color) -> some View {
        // Trim edge punctuation; internal hyphens/apostrophes survive (e.g.
        // "two-factor", "don't") because trimming only touches the ends.
        let cleaned = token.trimmingCharacters(in: CharacterSet.letters.inverted)
        if cleaned.count >= 2 {
            let key = cleaned.lowercased()
            let on = selected[key] != nil
            Button {
                if on { selected[key] = nil } else { selected[key] = cleaned }
            } label: {
                Text(token)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(on ? sel : base)
                    .underline(on, color: sel)
            }
            .buttonStyle(.plain)
        } else {
            Text(token).font(.callout.weight(.medium)).foregroundStyle(base)
        }
    }

    /// Split into display words on whitespace (keeps punctuation for a natural
    /// sentence look); the saved term is the word with edge punctuation trimmed.
    private func displayTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: Save bar

    private var saveBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.duoRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    Button("➕ Bộ mới") { newDeckTitle = ""; askNewDeck = true }
                    ForEach(decks.decks) { d in
                        Button(d.title) { selectedDeckID = d.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full.fill")
                        Text(deckLabel).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
                }

                Button(action: save) {
                    if isWorking { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                    else { Text("Lưu \(selected.count)").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.duoPrimary(enabled: canSave))
                .disabled(!canSave)
            }
            if !AppConfiguration.hasGeminiKey {
                Text("⚠️ Thêm API key trong Cài đặt để lưu từ.")
                    .font(.caption2.weight(.bold)).foregroundStyle(.duoGoldEdge)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .top) { Rectangle().fill(Color.duoSwan).frame(height: 2) }
        )
    }

    private var deckLabel: String {
        if let id = selectedDeckID, let d = decks.deck(id: id) { return d.title }
        return newDeckTitle.isEmpty ? "Bộ mới" : newDeckTitle
    }

    private func save() {
        error = nil
        isWorking = true
        let terms = selected.values.joined(separator: "\n")
        Task {
            do {
                let words = try await DeckAIService().generateWords(from: terms)
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
        if let id = selectedDeckID, decks.deck(id: id) != nil { return id }
        let title = newDeckTitle.trimmingCharacters(in: .whitespaces)
        return decks.createDeck(title: title.isEmpty ? "Từ vựng từ Chat" : title).id
    }
}
