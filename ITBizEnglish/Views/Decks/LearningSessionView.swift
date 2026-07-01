//
//  LearningSessionView.swift
//  ITBizEnglish
//
//  The learning engine UI, redesigned Duolingo-style: a chunky top progress
//  bar, a speech-bubble prompt, big selectable answer cards, and a colored
//  feedback panel that slides up from the bottom with a 3D CONTINUE button.
//
//  Interaction: for choice questions the user taps to SELECT, then presses
//  CHECK; typing has a CHECK button; the new-word flashcard has CONTINUE. This
//  is purely presentational — scoring & spaced-repetition logic are unchanged.
//

import SwiftUI
import UIKit
import ImageIO

struct LearningSessionView: View {
    @State private var vm: LearningSessionViewModel
    @State private var speech = SpeechSynthesizer()
    @Environment(\.dismiss) private var dismiss

    // Per-question input, reset whenever the step changes.
    @State private var selected: String?
    @State private var typedText = ""

    init(store: DeckStore, deckID: UUID, mode: LearningSessionViewModel.Mode = .learn) {
        _vm = State(initialValue: LearningSessionViewModel(deckID: deckID, store: store, mode: mode))
    }

    private var locked: Bool { vm.feedback != .none }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            VStack(spacing: Theme.Spacing.lg) {
                if !vm.isFinished { header }
                ScrollView {
                    content
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                        .padding(.bottom, 200)   // room for the docked panel
                }
            }
            .padding(.top, Theme.Spacing.sm)

            if !vm.isFinished { bottomBar }
        }
        .onChange(of: stepKey) { _, _ in
            selected = nil
            typedText = ""
        }
        // Typing, dictation & fill-blank: as soon as the user types the exact
        // answer, auto-submit.
        .onChange(of: typedText) { _, newValue in
            guard !locked, let target = autoSubmitTarget else { return }
            let typed = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let want = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !typed.isEmpty, typed == want { submitTyping() }
        }
    }

    // MARK: - Header (close + fat progress bar)

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.bold)).foregroundStyle(.duoHare)
            }
            DuoProgressBar(value: vm.progress)
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").foregroundStyle(.duoGold)
                Text("\(vm.correctThisSession)").monospacedDigit()
            }
            .font(.headline.weight(.heavy)).foregroundStyle(.duoGold)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Question content

    @ViewBuilder
    private var content: some View {
        switch vm.step {
        case .flashcard(let word):
            FlashcardCard(word: word, speech: speech)
                .transition(stepTransition)

        case .multipleChoice(let word, let options):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Chọn từ tiếng Anh đúng")
                BubblePrompt(text: word.meaning, speech: nil, word: nil)
                choiceList(options, correct: word.word)
            }
            .transition(stepTransition)

        case .reversedChoice(let word, let options):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Chọn nghĩa đúng")
                BubblePrompt(text: word.word, speech: speech, word: word.word)
                choiceList(options, correct: word.meaning)
            }
            .transition(stepTransition)

        case .tapping(let word, let tokens):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Ghép thành cụm đúng")
                BubblePrompt(text: word.meaning, speech: nil, word: nil)
                TappingExercise(target: word.word, tokens: tokens, locked: locked) { assembled in
                    submitTapping(assembled)
                }
                .id(word.id)
            }
            .transition(stepTransition)

        case .audioChoice(let word, let options):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Nghe và chọn nghĩa")
                SpeakerOrb(word: word, speech: speech)
                choiceList(options, correct: word.meaning)
            }
            .transition(stepTransition)

        case .typing(let word):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Gõ từ tiếng Anh")
                BubblePrompt(text: word.meaning, speech: nil, word: nil)
                TypingField(text: $typedText, locked: locked, feedback: vm.feedback, onSubmit: submitTyping)
            }
            .transition(stepTransition)

        case .audioTyping(let word):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Nghe và gõ lại từ")
                SpeakerOrb(word: word, speech: speech)
                TypingField(text: $typedText, locked: locked, feedback: vm.feedback, onSubmit: submitTyping)
            }
            .transition(stepTransition)

        case .fillBlank(let word, let sentence, _):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PromptHeading("Điền vào chỗ trống")
                FillBlankPrompt(sentence: sentence, meaning: word.meaning)
                TypingField(text: $typedText, locked: locked, feedback: vm.feedback, onSubmit: submitTyping)
            }
            .transition(stepTransition)

        case .finished:
            FinishedView(correct: vm.correctThisSession, total: vm.answeredCount) { dismiss() }
        }
    }

    /// Builds the selectable option cards with their current state.
    private func choiceList(_ options: [String], correct: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                DuoChoiceCard(state: choiceState(option, correct: correct)) {
                    guard !locked else { return }
                    submitChoice(option)   // tap = auto-submit
                } content: {
                    Text(option)
                }
                // Hardware keyboard: press 1–4 to pick that option.
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
    }

    private func choiceState(_ option: String, correct: String) -> DuoChoiceState {
        if locked {
            if option == correct { return .correct }
            if option == selected { return .wrong }
            return .dimmed
        }
        return option == selected ? .selected : .normal
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    /// A stable identity for the current question, to reset input on change.
    private var stepKey: String {
        switch vm.step {
        case .flashcard(let w):           return "f-\(w.id)"
        case .multipleChoice(let w, _):   return "m-\(w.id)"
        case .reversedChoice(let w, _):   return "r-\(w.id)"
        case .audioChoice(let w, _):      return "a-\(w.id)"
        case .typing(let w):              return "t-\(w.id)"
        case .audioTyping(let w):         return "at-\(w.id)"
        case .tapping(let w, _):          return "p-\(w.id)"
        case .fillBlank(let w, _, _):     return "fb-\(w.id)"
        case .finished:                   return "done"
        }
    }

    // MARK: - Bottom action / feedback bar

    @ViewBuilder
    private var bottomBar: some View {
        if locked {
            FeedbackPanel(
                correct: vm.feedback == .correct,
                word: vm.lastWord,
                speech: speech,
                onContinue: advance
            )
            .transition(.move(edge: .bottom))
        } else {
            actionButton
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                .background(Color(.systemBackground).opacity(0.01))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch vm.step {
        case .flashcard:
            Button("Tiếp tục") { withAnimation { vm.flashcardNext() } }
                .buttonStyle(.duoGreen)
                .keyboardShortcut(.defaultAction)   // Return advances

        case .multipleChoice, .reversedChoice, .audioChoice, .tapping:
            // Choices auto-submit on tap; tapping submits when complete.
            EmptyView()

        case .typing, .audioTyping, .fillBlank:
            Button("Kiểm tra") { submitTyping() }
                .buttonStyle(.duoPrimary(enabled: !typedText.trimmingCharacters(in: .whitespaces).isEmpty))
                .disabled(typedText.trimmingCharacters(in: .whitespaces).isEmpty)

        case .finished:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func submitChoice(_ choice: String) {
        selected = choice
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch vm.step {
            case .multipleChoice: vm.answerMultipleChoice(choice)
            case .reversedChoice: vm.answerReversedChoice(choice)
            case .audioChoice:    vm.answerAudioChoice(choice)
            default: break
            }
        }
        playFeedbackSound()
    }

    private func submitTapping(_ assembled: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            vm.answerTapping(assembled)
        }
        playFeedbackSound()
    }

    /// Exact expected answer for the current free-entry step (typing, dictation,
    /// or fill-in-the-blank) — drives auto-submit. nil for all other steps.
    private var autoSubmitTarget: String? {
        switch vm.step {
        case .typing(let w), .audioTyping(let w): return w.word
        case .fillBlank(_, _, let answer):        return answer
        default: return nil
        }
    }

    private func submitTyping() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch vm.step {
            case .typing:      vm.answerTyping(typedText)
            case .audioTyping: vm.answerAudioTyping(typedText)
            case .fillBlank:   vm.answerFillBlank(typedText)
            default: break
            }
        }
        playFeedbackSound()
    }

    private func playFeedbackSound() {
        if vm.feedback == .correct { SoundFX.correct() } else { SoundFX.wrong() }
    }

    private func advance() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            vm.continueAfterFeedback()
        }
    }
}

// MARK: - Prompt heading

private struct PromptHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .foregroundStyle(.duoInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Speech-bubble prompt

private struct BubblePrompt: View {
    let text: String
    let speech: SpeechSynthesizer?
    let word: String?

    /// A random mascot gif chosen once per question.
    @State private var mascot = AnimatedGIF.randomWaiting()

    private let tailWidth: CGFloat = 13

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            AnimatedGIF(name: mascot)
                .frame(width: 128, height: 128)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.duoInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let speech, let word {
                    Button { speech.speak(word, id: word) } label: {
                        Label("Nghe", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.duoBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.md)
            .padding(.leading, tailWidth + Theme.Spacing.sm)
            .background(ChatBubble(tailWidth: tailWidth).fill(Color(.systemBackground)))
            .overlay(ChatBubble(tailWidth: tailWidth).strokeBorder(Color.duoSwan, lineWidth: 2))
        }
    }
}

/// A rounded speech bubble with a triangular tail on the left edge, pointing
/// toward the mascot beside it.
private struct ChatBubble: InsettableShape {
    var tailWidth: CGFloat = 13
    var cornerRadius: CGFloat = 18
    /// Half-height of the tail where it meets the body.
    var tailSpread: CGFloat = 10
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> ChatBubble {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cr = min(cornerRadius, (r.height - 2 * insetAmount) / 2)
        let left = r.minX + tailWidth            // body's left edge
        let cy = r.midY

        // One continuous outline: body corners + tail, so a stroke produces a
        // single clean edge with no internal seam where the tail meets the body.
        let tl = CGPoint(x: left,  y: r.minY)
        let tr = CGPoint(x: r.maxX, y: r.minY)
        let br = CGPoint(x: r.maxX, y: r.maxY)
        let bl = CGPoint(x: left,  y: r.maxY)

        var p = Path()
        p.move(to: CGPoint(x: left + cr, y: r.minY))      // just past the top-left corner
        p.addArc(tangent1End: tr, tangent2End: br, radius: cr)  // top-right
        p.addArc(tangent1End: br, tangent2End: bl, radius: cr)  // bottom-right
        p.addArc(tangent1End: bl, tangent2End: tl, radius: cr)  // bottom-left
        // Up the left edge, poke out to the tail tip, then continue up.
        p.addLine(to: CGPoint(x: left, y: cy + tailSpread))
        p.addLine(to: CGPoint(x: r.minX, y: cy))                // tip → mascot
        p.addLine(to: CGPoint(x: left, y: cy - tailSpread))
        p.addArc(tangent1End: tl, tangent2End: tr, radius: cr)  // top-left
        p.closeSubpath()
        return p
    }
}

// MARK: - Audio orb (listen & choose)

private struct SpeakerOrb: View {
    let word: DeckWord
    let speech: SpeechSynthesizer

    var body: some View {
        HStack {
            Spacer()
            Button { speech.speak(word.word, id: word.id.uuidString) } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 44)).foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(
                        ZStack {
                            Circle().fill(Color.duoBlueEdge).offset(y: 5)   // 3D lip behind
                            Circle().fill(Color.duoBlue)
                        }
                    )
            }
            .buttonStyle(.plain)
            // Auto-play on first appear AND whenever the word changes. Two audio
            // steps in a row reuse this same view (only `word` updates), so a
            // plain `.onAppear` would fire only for the first one.
            .onChange(of: word.id, initial: true) { _, _ in
                speech.speak(word.word, id: word.id.uuidString)
            }
            Spacer()
        }
    }
}

// MARK: - Fill-in-the-blank prompt

/// Shows the word's example sentence with a blank where the word was, plus the
/// Vietnamese meaning as a hint so the user knows which word to recall.
private struct FillBlankPrompt: View {
    let sentence: String
    let meaning: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(sentence)
                .font(.title3.weight(.bold)).foregroundStyle(.duoInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.duoGold)
                Text(meaning).font(.subheadline.weight(.bold)).foregroundStyle(.duoWolf)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .duoCard()
    }
}

// MARK: - Typing field

private struct TypingField: View {
    @Binding var text: String
    let locked: Bool
    let feedback: LearningSessionViewModel.Feedback
    /// Called when the user presses Return — submits the typed answer.
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    private var border: Color {
        guard locked else { return focused ? .duoBlue : .duoSwan }
        return feedback == .correct ? .duoGreen : .duoRed
    }

    var body: some View {
        TextField("Nhập tại đây…", text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .submitLabel(.done)
            .onSubmit { onSubmit() }   // hardware/on-screen Return submits
            .font(.title3.weight(.bold))
            .foregroundStyle(.duoInk)
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Color.duoPolar))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(border, lineWidth: 2))
            .disabled(locked)
            .onAppear { focused = true }
    }
}

// MARK: - New-word flashcard

private struct FlashcardCard: View {
    let word: DeckWord
    let speech: SpeechSynthesizer

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                Text("TỪ MỚI")
                    .font(.subheadline.weight(.heavy)).foregroundStyle(.duoGold)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.duoGold.opacity(0.18)))
                GrowthBadge(progress: word.correctCount)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Text(word.word).font(.system(size: 34, weight: .heavy)).foregroundStyle(.duoInk)
                Button { speech.speak(word.word, id: word.id.uuidString) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title2).foregroundStyle(.duoBlue)
                }.buttonStyle(.plain)
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

            Text(word.meaning)
                .font(.title3.weight(.bold)).foregroundStyle(.duoInk)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            if !word.example.isEmpty {
                Text("“\(word.example)”")
                    .font(.callout.italic()).foregroundStyle(.duoWolf)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .duoCard()
        .padding(.top, Theme.Spacing.lg)
        // Auto-play on first appear AND whenever the word changes — back-to-back
        // flashcards reuse this same view, so `.onAppear` alone would fire once.
        .onChange(of: word.id, initial: true) { _, _ in
            speech.speak(word.word, id: word.id.uuidString)
        }
    }
}

// MARK: - Tapping (build the phrase)

private struct TappingExercise: View {
    let target: String
    let tokens: [String]
    let locked: Bool
    let onSubmit: (String) -> Void

    private struct Tile: Identifiable, Equatable { let id = UUID(); let text: String }
    @State private var bank: [Tile] = []
    @State private var chosen: [Tile] = []
    @State private var submitted = false
    @State private var celebrating: Set<UUID> = []

    private var targetCount: Int { target.split(separator: " ").count }

    /// Did the user assemble the phrase correctly?
    private var isCorrect: Bool {
        chosen.map(\.text).joined(separator: " ").lowercased()
            == target.lowercased()
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Assembled answer zone.
            FlowLayout(spacing: 8) {
                ForEach(chosen) { tileView($0, inChosen: true) }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(Theme.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.duoSwan, lineWidth: 2))

            // Token bank.
            FlowLayout(spacing: 8) {
                ForEach(bank) { tileView($0, inChosen: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if bank.isEmpty && chosen.isEmpty { bank = tokens.map { Tile(text: $0) } }
        }
        .onChange(of: chosen.count) { _, count in
            if !submitted, !locked, count == targetCount {
                submitted = true
                onSubmit(chosen.map(\.text).joined(separator: " "))
                if isCorrect { celebrateChosen() }
            }
        }
    }

    /// Pop the assembled tiles one after another, left → right.
    private func celebrateChosen() {
        for (i, tile) in chosen.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                celebrating.insert(tile.id)
            }
        }
    }

    private func tileView(_ tile: Tile, inChosen: Bool) -> some View {
        let correct = inChosen && submitted && isCorrect
        return Button {
            guard !locked, !submitted else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if inChosen {
                    chosen.removeAll { $0.id == tile.id }; bank.append(tile)
                } else {
                    bank.removeAll { $0.id == tile.id }; chosen.append(tile)
                }
            }
        } label: {
            Text(tile.text)
                .font(.body.weight(.bold)).foregroundStyle(correct ? .duoOkText : .duoInk)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(correct ? Color.duoOkFill : Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(correct ? Color.duoOkBorder : Color.duoSwan, lineWidth: 2))
                .correctCelebration(trigger: celebrating.contains(tile.id), cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom feedback panel

private struct FeedbackPanel: View {
    let correct: Bool
    let word: DeckWord?
    let speech: SpeechSynthesizer
    let onContinue: () -> Void

    private var fill: Color { correct ? Color.brand.opacity(0.15) : .duoWrongFill }
    private var tint: Color { correct ? .brand : .duoWrongText }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title).foregroundStyle(tint)
                    .symbolEffect(.bounce, value: correct)
                Text(correct ? "Tuyệt vời!" : "Đáp án đúng:")
                    .font(.title3.weight(.heavy)).foregroundStyle(tint)
                Spacer()
                if let word {
                    GrowthBadge(progress: word.correctCount)
                }
            }

            // Always show the word's detail: pronunciation + meaning + example.
            if let word {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(word.word).font(.headline.weight(.heavy)).foregroundStyle(tint)
                        if !word.pronunciation.isEmpty {
                            Text(word.pronunciation).font(.subheadline).foregroundStyle(tint.opacity(0.85))
                        }
                        Button { speech.speak(word.word, id: "fb-\(word.id)") } label: {
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(word.meaning).font(.subheadline.weight(.bold)).foregroundStyle(tint)
                    if !word.example.isEmpty {
                        Text("“\(word.example)”")
                            .font(.subheadline.italic()).foregroundStyle(tint.opacity(0.9))
                    }
                }
            }

            Button(correct ? "Tiếp tục" : "Đã hiểu", action: onContinue)
                .buttonStyle(correct ? .brand : .duoRed)
                .keyboardShortcut(.defaultAction)   // Return moves on after feedback
        }
        .padding(Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque base + tint so the answer cards behind don't bleed through.
        .background(
            ZStack {
                Color(.systemBackground)
                fill
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Session complete

private struct FinishedView: View {
    let correct: Int
    let total: Int
    let onDone: () -> Void

    /// Did the user do well this session? (≥ 60% correct)
    private var didWell: Bool {
        total > 0 && Double(correct) / Double(total) >= 0.6
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(didWell ? "Làm tốt lắm! 🎉" : "Cố thêm chút nữa nhé!")
                .font(.title.weight(.heavy)).foregroundStyle(.duoInk)
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.md) {
                statPill(title: "ĐÚNG", value: "\(correct)", color: .duoGreen)
                statPill(title: "TỔNG", value: "\(total)", color: .duoBlue)
            }

            // Mascot reaction — happy when you did well, grumpy when you didn't.
            AnimatedGIF(name: didWell ? "happy" : "angry")
                .frame(width: 240, height: 240)
                .padding(.vertical, Theme.Spacing.sm)

            Button("Tiếp tục", action: onDone)
                .buttonStyle(.duoGreen)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .onAppear { SoundFX.completed() }
    }

    private func statPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.9))
            Text(value).font(.title2.weight(.heavy)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(color))
    }
}

// MARK: - Growth badge (Memrise-style seed → flower)

/// Visualises how well a word is learned as a growing plant: seed → sprout →
/// leaves → bud → bloom. `progress` is the word's correctCount (0...goal).
struct GrowthBadge: View {
    let progress: Int
    var goal: Int = DeckWord.masteryGoal

    private var stage: Int { max(0, min(progress, goal)) }
    private var t: CGFloat { goal == 0 ? 0 : CGFloat(stage) / CGFloat(goal) }
    private var bloomed: Bool { stage >= goal && goal > 0 }

    private let soil = Color(hex: 0x8B5A2B)

    var body: some View {
        ZStack(alignment: .bottom) {
            // soil mound
            Ellipse().fill(soil).frame(width: 44, height: 14)

            if stage == 0 {
                Capsule().fill(Color(hex: 0x6B4423))
                    .frame(width: 9, height: 13).offset(y: -5)   // seed
            } else if bloomed {
                stem(height: 44)
                flower.offset(y: -42)
            } else {
                let h = 12 + t * 34
                stem(height: h)
                if stage >= 2 {
                    leaf.rotationEffect(.degrees(-32)).offset(x: -9, y: -h * 0.45)
                }
                if stage >= 3 {
                    leaf.rotationEffect(.degrees(32)).offset(x: 9, y: -h * 0.7)
                }
                if stage >= 4 {
                    Circle().fill(Color.duoGold).frame(width: 12, height: 12).offset(y: -h - 2)
                }
            }
        }
        .frame(width: 56, height: 64)
        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: stage)
    }

    private func stem(height: CGFloat) -> some View {
        Capsule().fill(Color.duoGreen).frame(width: 5, height: height).offset(y: -6)
    }
    private var leaf: some View {
        Ellipse().fill(Color.duoGreen).frame(width: 17, height: 9)
    }
    private var flower: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(Color.duoRed)
                    .frame(width: 9, height: 18)
                    .offset(y: -9)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle().fill(Color.duoGold).frame(width: 13, height: 13)
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - Animated GIF

/// Plays a bundled .gif (decoded with ImageIO) in a UIImageView. Decoded
/// animations are cached so repeat use is cheap.
struct AnimatedGIF: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.image = Self.animatedImage(named: name)
        // Let the SwiftUI .frame fully control the size, not the image's pixels.
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            view.setContentHuggingPriority(.defaultLow, for: axis)
            view.setContentCompressionResistancePriority(.defaultLow, for: axis)
        }
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image == nil { uiView.image = Self.animatedImage(named: name) }
    }

    /// Honor the SwiftUI-proposed (framed) size instead of the gif's pixel size.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 64, height: 64))
    }

    /// A random "waitingN" gif name (N = 1...7).
    static func randomWaiting() -> String { "waiting\(Int.random(in: 1...7))" }

    /// A random "clapN" celebration character (N = 1...3).
    static func randomClap() -> String { "clap\(Int.random(in: 1...3))" }

    private static var cache: [String: UIImage] = [:]

    static func animatedImage(named: String) -> UIImage? {
        if let cached = cache[named] { return cached }
        guard let url = Bundle.main.url(forResource: named, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var duration = 0.0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            duration += frameDelay(source, i)
        }
        let image = frames.count > 1
            ? UIImage.animatedImage(with: frames, duration: duration)
            : frames.first
        if let image { cache[named] = image }
        return image
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

#Preview {
    LearningSessionView(store: DeckStore(), deckID: WordDeck.sample.id)
}
