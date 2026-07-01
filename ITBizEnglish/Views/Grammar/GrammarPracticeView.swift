//
//  GrammarPracticeView.swift
//  ITBizEnglish
//
//  The Duolingo-style practice runner for a grammar lesson: one exercise per
//  screen, increasing difficulty, with a progress bar at the top and a feedback
//  panel that never just says "wrong" — it explains why, shows the rule, the
//  correct version, and one more example. Open-ended writing is graded by AI.
//  Finishes with a 30-second summary, flashcards, a score, and a spaced-
//  repetition review plan to save.
//

import SwiftUI

struct GrammarPracticeView: View {
    let route: GrammarRoute
    /// The exact exercises to run — the lesson's own set, or a fresh AI-generated
    /// set for a chosen context (picked in GrammarPracticeSetupSheet).
    var exercises: [GrammarExercise]
    @Bindable var store: GrammarStore
    /// Set when launched from an already-saved lesson.
    var savedID: UUID?
    /// Set when running a saved AI-generated exercise set (records its score).
    var setID: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var creditSum = 0.0     // 0…count, fractional for AI-graded items
    @State private var finished = false
    @State private var localSavedID: UUID?
    private var progress: Double {
        exercises.isEmpty ? 1 : Double(index) / Double(exercises.count)
    }
    private var finalScore: Int {
        exercises.isEmpty ? 0 : Int((creditSum / Double(exercises.count) * 100).rounded())
    }

    var body: some View {
        ZStack {
            AppBackground()
            if finished || exercises.isEmpty {
                finishView
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    header
                    GrammarExerciseView(
                        exercise: exercises[index],
                        pattern: route.pattern,
                        onNext: { credit in advance(credit) }
                    )
                    .id(exercises[index].id)   // fresh state per question
                }
            }
        }
        .navigationTitle("Luyện tập")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear { localSavedID = savedID }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundStyle(.duoHare)
            }
            DuoProgressBar(value: progress, tint: .brand)
            Text("\(min(index + 1, exercises.count))/\(exercises.count)")
                .font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(.duoWolf)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    private func advance(_ credit: Double) {
        creditSum += max(0, min(1, credit))
        withAnimation {
            if index + 1 >= exercises.count { finished = true }
            else { index += 1 }
        }
    }

    // MARK: - Finish

    private var finishView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    AnimatedGIF(name: finalScore >= 60 ? "gym" : "waiting1").frame(width: 170, height: 170)
                    Text(finalScore >= 80 ? "Xuất sắc!" : (finalScore >= 60 ? "Làm tốt lắm!" : "Cố thêm chút nữa nhé!"))
                        .font(.title.weight(.heavy)).foregroundStyle(.duoInk)
                    HStack(spacing: 6) {
                        Text("Điểm").font(.subheadline.weight(.bold)).foregroundStyle(.duoWolf)
                        Text("\(finalScore)")
                            .font(.title.weight(.heavy).monospacedDigit())
                            .foregroundStyle(scoreColor(finalScore))
                        Text("/100").font(.subheadline.weight(.bold)).foregroundStyle(.duoWolf)
                    }
                }
                .padding(.top, Theme.Spacing.md)

                GrammarSummaryCard(pattern: route.pattern, summary: route.lesson.summary)

                reviewPlanCard

                Button("Xong") { dismiss() }
                    .buttonStyle(.duo(.duoGreen, edge: .duoGreenEdge))
            }
            .padding(Theme.Spacing.md)
        }
        .onAppear {
            SoundFX.completed()
            if let id = localSavedID {
                store.recordScore(finalScore, forSaved: id)
                if let sid = setID { store.recordExerciseSetScore(finalScore, setID: sid, inSaved: id) }
            }
        }
    }

    // MARK: - Spaced-repetition review plan

    private var reviewPlanCard: some View {
        let saved = localSavedID.flatMap { store.saved(id: $0) }
        let stage = saved?.reviewStage ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.duoIndigo))
                Text("Lịch ôn tập").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
            }
            Text("Ôn lại đúng lúc giúp nhớ lâu hơn (lặp lại ngắt quãng).")
                .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)

            HStack(spacing: Theme.Spacing.sm) {
                reviewChip("Ngày mai", active: stage == 0)
                reviewChip("3 ngày", active: stage == 1)
                reviewChip("7 ngày", active: stage >= 2)
            }

            if let saved {
                Label(saved.nextReviewLabel, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.duoGreen)
                Button {
                    Haptics.tap()
                    store.markReviewed(id: saved.id)
                } label: {
                    Label("Đã ôn xong — lên lịch lần sau", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge))
            } else {
                Button {
                    Haptics.tap()
                    let id = store.save(route.lesson, pattern: route.pattern, request: route.request)
                    store.recordScore(finalScore, forSaved: id)
                    withAnimation { localSavedID = id }
                } label: {
                    Label("Lưu để ôn lại", systemImage: "bookmark.fill")
                }
                .buttonStyle(.duoPrimary(enabled: true))
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func reviewChip(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.heavy)).foregroundStyle(active ? .white : .duoWolf)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? AnyShapeStyle(Color.duoIndigo) : AnyShapeStyle(Color.duoPolar)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(active ? Color.duoIndigoEdge : Color.duoSwan, lineWidth: 2))
    }

    private func scoreColor(_ s: Int) -> Color { s >= 85 ? .duoGreen : (s >= 60 ? .duoGold : .duoRed) }
}

// MARK: - One exercise

/// Renders a single exercise of any kind, owns its own answer state, and shows
/// the check / feedback / continue chrome. Calls `onNext` with a 0…1 credit when
/// the learner moves on.
private struct GrammarExerciseView: View {
    let exercise: GrammarExercise
    let pattern: String
    let onNext: (Double) -> Void

    @State private var speech = SpeechSynthesizer()

    // Tap-choice state.
    @State private var selected: Int?
    @State private var graded = false
    @State private var isCorrect = false

    // Word-order state.
    private struct Tile: Identifiable, Equatable { let id = UUID(); let text: String }
    @State private var bank: [Tile] = []
    @State private var chosen: [Tile] = []
    @State private var builtTiles = false

    // Open-ended state.
    @State private var attempt = ""
    @State private var lines = ["", "", ""]
    @State private var feedback: AIFeedback?
    @State private var checking = false
    @State private var aiError: String?

    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    kindBadge
                    promptBlock
                    answerArea
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, 160)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .onAppear(perform: buildIfNeeded)
    }

    private var kindBadge: some View {
        Text(exercise.kindLabel.uppercased())
            .font(.caption2.weight(.heavy)).foregroundStyle(.brand)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.brand.opacity(0.14)))
    }

    // MARK: Prompt

    private var promptBlock: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(exercise.prompt)
                .font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if promptIsEnglish {
                Button { speech.speak(exercise.prompt.replacingOccurrences(of: "___", with: "blank"), id: "ex-\(exercise.id)") } label: {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.duoBlue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var promptIsEnglish: Bool {
        switch exercise.kind {
        case .fillBlank, .enToVi, .findMistake, .conversation: return true
        default: return false
        }
    }

    // MARK: Answer area (per kind)

    @ViewBuilder
    private var answerArea: some View {
        switch exercise.kind {
        case .wordOrder, .viToEn:
            wordOrderArea
        case .writeSentence:
            writeArea(fieldCount: 1)
        case .miniChallenge:
            writeArea(fieldCount: 3)
        default:
            optionsArea
        }
    }

    // Tap-to-choose options.
    private var optionsArea: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array((exercise.options ?? []).enumerated()), id: \.offset) { i, opt in
                DuoChoiceCard(state: optionState(i)) {
                    guard !graded else { return }
                    Haptics.tap()
                    selected = i
                } content: {
                    Text(opt).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func optionState(_ i: Int) -> DuoChoiceState {
        guard graded else { return selected == i ? .selected : .normal }
        if i == exercise.answerIndex { return .correct }
        if i == selected { return .wrong }
        return .dimmed
    }

    // Word-order arranger.
    private var wordOrderArea: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Answer line.
            FlowLayout(spacing: 8) {
                ForEach(chosen) { tile in
                    tileButton(tile, inChosen: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.duoSwan).frame(height: 2) }

            // Bank.
            FlowLayout(spacing: 8) {
                ForEach(bank) { tile in
                    tileButton(tile, inChosen: false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
    }

    private func tileButton(_ tile: Tile, inChosen: Bool) -> some View {
        Button {
            guard !graded else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if inChosen {
                    if let i = chosen.firstIndex(of: tile) { bank.append(chosen.remove(at: i)) }
                } else {
                    if let i = bank.firstIndex(of: tile) { chosen.append(bank.remove(at: i)) }
                }
            }
        } label: {
            Text(tile.text)
                .font(.body.weight(.bold)).foregroundStyle(.duoInk)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoSwan).offset(y: 2))
                .opacity(inChosen ? 1 : 0.95)
        }
        .buttonStyle(.plain)
    }

    // Open-ended writing.
    private func writeArea(fieldCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let vi = exercise.vietnamese, !vi.isEmpty {
                Label(vi, systemImage: "character.bubble")
                    .font(.callout.weight(.bold)).foregroundStyle(.duoWolf)
            }
            if fieldCount == 1 {
                writeField(text: $attempt, placeholder: "Viết câu tiếng Anh của bạn…")
            } else {
                ForEach(0..<fieldCount, id: \.self) { i in
                    writeField(text: $lines[i], placeholder: "Câu \(i + 1)…")
                }
            }
            if let feedback { feedbackCard(feedback) }
            if let aiError {
                Label(aiError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.duoRed)
            }
        }
    }

    private func writeField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(1...4).font(.body).focused($typing)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
            .disabled(graded)
    }

    // MARK: Bottom bar (check / feedback / continue)

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if graded, !exercise.isOpenEnded {
                autoFeedbackPanel
            }
            actionButton
        }
        .padding(Theme.Spacing.md)
        .background(
            (graded && !exercise.isOpenEnded
                ? (isCorrect ? Color.duoOkFill : Color.duoWrongFill)
                : Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        if exercise.isOpenEnded {
            if feedback == nil {
                Button { checkOpen() } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if checking { ProgressView().tint(.white); Text("Đang chấm…") }
                        else { Image(systemName: "checkmark.seal"); Text("Kiểm tra với AI") }
                    }
                }
                .buttonStyle(.duoPrimary(enabled: canCheckOpen && !checking))
                .disabled(!canCheckOpen || checking)
            } else {
                Button("Tiếp tục") { onNext((Double(feedback?.score ?? 0)) / 100) }
                    .buttonStyle(.duo(.duoGreen, edge: .duoGreenEdge))
            }
        } else if graded {
            Button(isCorrect ? "Tiếp tục" : "Đã hiểu") { onNext(isCorrect ? 1 : 0) }
                .buttonStyle(isCorrect ? .duo(.duoGreen, edge: .duoGreenEdge) : .duo(.duoRed, edge: .duoRedEdge))
        } else {
            Button("Kiểm tra") { gradeAuto() }
                .buttonStyle(.duoPrimary(enabled: canGrade))
                .disabled(!canGrade)
        }
    }

    private var autoFeedbackPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isCorrect ? "Chính xác!" : "Chưa đúng",
                  systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.weight(.heavy)).foregroundStyle(isCorrect ? .duoOkText : .duoWrongText)
            if !isCorrect, let answer = correctAnswerText {
                Text("Đáp án: \(answer)").font(.callout.weight(.bold)).foregroundStyle(.duoInk)
            }
            if let ex = exercise.explanation, !ex.isEmpty {
                Text(ex).font(.subheadline.weight(.medium)).foregroundStyle(.duoInk)
            }
            if let more = exercise.example, !more.isEmpty {
                Label(more, systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(isCorrect ? .duoOkText : .duoWrongText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedbackCard(_ fb: AIFeedback) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("\(fb.emoji) \(fb.verdict)").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
                Text("\(fb.score)/100").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(fb.ratingColor)
            }
            DuoProgressBar(value: Double(fb.score) / 100, tint: fb.ratingColor, height: 10)
            if !fb.correctedVersion.isEmpty {
                Divider()
                Text("GỢI Ý TỰ NHIÊN").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                Text(fb.correctedVersion).font(.callout.weight(.bold)).foregroundStyle(.duoInk).textSelection(.enabled)
            }
            if !fb.notes.isEmpty {
                Divider()
                ForEach(fb.notes, id: \.self) { note in
                    Label(note, systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.duoInk)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
    }

    // MARK: Grading

    private var canGrade: Bool {
        switch exercise.kind {
        case .wordOrder, .viToEn: return !chosen.isEmpty
        default:                  return selected != nil
        }
    }
    private var canCheckOpen: Bool {
        switch exercise.kind {
        case .writeSentence:  return !attempt.trimmingCharacters(in: .whitespaces).isEmpty && AppConfiguration.hasGeminiKey
        case .miniChallenge:  return lines.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } && AppConfiguration.hasGeminiKey
        default:              return false
        }
    }

    private var correctAnswerText: String? {
        switch exercise.kind {
        case .wordOrder, .viToEn:
            return exercise.answer
        case .findMistake:
            return exercise.answer ?? (exercise.answerIndex.flatMap { exercise.options?[safe: $0] })
        default:
            return exercise.answerIndex.flatMap { exercise.options?[safe: $0] }
        }
    }

    private func gradeAuto() {
        typing = false
        switch exercise.kind {
        case .wordOrder, .viToEn:
            let attemptText = chosen.map(\.text).joined(separator: " ")
            isCorrect = normalize(attemptText) == normalize(exercise.answer ?? "")
        default:
            isCorrect = (selected != nil && selected == exercise.answerIndex)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { graded = true }
        if isCorrect { SoundFX.correct() } else { SoundFX.wrong() }
    }

    private func checkOpen() {
        typing = false
        aiError = nil
        checking = true
        let text = exercise.kind == .miniChallenge
            ? lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.enumerated()
                  .map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            : attempt
        Task {
            do {
                let fb = try await GrammarAIService().evaluate(pattern: pattern, instruction: exercise.prompt, attempt: text)
                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { feedback = fb }
                    checking = false
                    if fb.score >= 60 { SoundFX.correct() } else { SoundFX.wrong() }
                }
            } catch {
                await MainActor.run {
                    aiError = (error as? LocalizedError)?.errorDescription ?? "Không chấm được. Thử lại nhé."
                    checking = false
                }
            }
        }
    }

    private func buildIfNeeded() {
        guard !builtTiles, exercise.kind == .wordOrder || exercise.kind == .viToEn else { return }
        builtTiles = true
        bank = exercise.arrangeTokens.shuffled().map { Tile(text: $0) }
        chosen = []
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
