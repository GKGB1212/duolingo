//
//  LearningSessionViewModel.swift
//  ITBizEnglish
//
//  The learning engine for a deck. Builds a Memrise-style session: words are
//  taken in LIST ORDER (not shuffled) and the session interleaves new-word
//  intros with quizzes in small batches — so the user doesn't see a clump of
//  new words followed by a clump of exercises, but rather: introduce a few
//  words, then practise them, then introduce the next few, and so on.
//
//  Scoring rules (per spec):
//   - correctCount 0..10. New word (0) is introduced via a flashcard.
//   - Correct answer: +1. Reaching 10 => mastered, schedule a review.
//   - Wrong answer: reset correctCount to 0 (word must be re-learned).
//   - Review spacing grows 1 → 3 → 7 → 14 → ×2 days on each correct review.
//

import Foundation
import Observation

@MainActor
@Observable
final class LearningSessionViewModel {

    // MARK: - Step the UI should render

    enum Mode { case learn, review, difficult }

    enum Step: Equatable {
        case flashcard(DeckWord)
        case multipleChoice(word: DeckWord, options: [String])   // options are English words
        case reversedChoice(word: DeckWord, options: [String])   // prompt English, options Vietnamese
        case audioChoice(word: DeckWord, options: [String])      // options are Vietnamese meanings
        case typing(DeckWord)
        case audioTyping(DeckWord)                               // hear the word, type what you heard
        case tapping(word: DeckWord, tokens: [String])           // build the English phrase
        case fillBlank(word: DeckWord, sentence: String, answer: String) // type the word missing from its example
        case finished
    }

    enum Feedback: Equatable { case none, correct, incorrect }

    /// A single planned action in the session timeline.
    private enum PlannedStep {
        case present(UUID)              // flashcard intro for a new word
        case quiz(UUID, QuizKind)       // an exercise on a word
    }
    private enum QuizKind { case multipleChoice, reversedChoice, audioChoice, typing, audioTyping, tapping, fillBlank }

    // MARK: - State
    private(set) var step: Step = .finished
    private(set) var feedback: Feedback = .none
    /// The correct answer to reveal after a wrong response.
    private(set) var revealedAnswer: String = ""
    /// Full detail of the word just answered — shown when the user is wrong.
    private(set) var lastWord: DeckWord?

    private(set) var answeredCount = 0
    private(set) var correctThisSession = 0

    let mode: Mode

    // MARK: - Session internals
    private let deckID: UUID
    private let store: DeckStore
    private var plan: [PlannedStep] = []   // ordered timeline of actions
    private var cursor = 0                  // index of the current planned step
    private var retried: Set<UUID> = []     // ids already requeued once after a miss
    private let plannedCount: Int           // initial plan length (for the progress bar)

    /// How many distinct words a single session studies (not necessarily to
    /// 10/10 — remaining mastery carries over to later sessions).
    private let sessionSize = 6
    /// New words are introduced two at a time, Memrise-style.
    private let batchSize = 2
    /// Max words pulled into each interleaved "mix" review round.
    private let mixCap = 4

    init(deckID: UUID, store: DeckStore, mode: Mode = .learn) {
        self.deckID = deckID
        self.store = store
        self.mode = mode

        let source: [DeckWord]
        switch mode {
        case .learn:     source = store.deck(id: deckID)?.studyableWords ?? []
        case .review:    source = store.deck(id: deckID)?.reviewableWords ?? []
        case .difficult: source = store.deck(id: deckID)?.difficultWords ?? []
        }
        // List order — take the first N studyable words (no shuffle).
        let words = Array(source.prefix(sessionSize))
        let builtPlan = Self.buildPlan(words: words, batchSize: batchSize, mixCap: mixCap)
        self.plan = builtPlan
        self.plannedCount = max(builtPlan.count, 1)
        advance()
    }

    // MARK: - Plan building

    /// Builds a Memrise-style interleaved timeline.
    ///
    /// For each batch of `batchSize` words (in list order):
    ///   1. Introduce any NEW words (flashcard).
    ///   2. Quiz each word in the batch (recognition: word-choice or audio).
    ///   3. From the 2nd batch on, add a shuffled "mix" round that re-tests the
    ///      words seen so far (capped at `mixCap`) — so earlier words keep coming
    ///      back, jumbled in with the new ones.
    ///
    /// Words aren't expected to hit 10/10 here; their progress carries to later
    /// sessions.
    private static func buildPlan(words: [DeckWord], batchSize: Int, mixCap: Int) -> [PlannedStep] {
        var plan: [PlannedStep] = []
        var seen: [UUID] = []
        var index = 0
        var isFirstBatch = true

        while index < words.count {
            let batch = Array(words[index..<min(index + batchSize, words.count)])

            // 1) Introduce new words.
            for w in batch where w.isNew { plan.append(.present(w.id)) }
            // 2) Recognition quiz for each word in this batch.
            for w in batch { plan.append(.quiz(w.id, recognitionKind())) }

            seen.append(contentsOf: batch.map(\.id))

            // 3) Mixed review of everything seen so far (shuffled, capped).
            if !isFirstBatch {
                for id in seen.shuffled().prefix(mixCap) {
                    plan.append(.quiz(id, anyKind()))
                }
            }
            isFirstBatch = false
            index += batchSize
        }
        return plan
    }

    /// Easier recognition question right after a word is introduced.
    private static func recognitionKind() -> QuizKind {
        Bool.random() ? .multipleChoice : .audioChoice
    }

    /// Any question type for mixed review rounds (includes recall by typing/tapping
    /// and fill-in-the-blank). `fillBlank` falls back to `typing` in `advance()`
    /// when the word has no usable example, so it's safe to offer here always.
    private static func anyKind() -> QuizKind {
        [.multipleChoice, .reversedChoice, .audioChoice, .typing, .audioTyping, .tapping, .fillBlank].randomElement() ?? .multipleChoice
    }

    // MARK: - Progress

    /// 0...1 for the session progress bar.
    var progress: Double {
        min(1, Double(cursor) / Double(plannedCount))
    }

    var isFinished: Bool { step == .finished }

    // MARK: - Driving the session

    /// Reads the planned step at the cursor and builds the concrete UI step.
    private func advance() {
        feedback = .none
        revealedAnswer = ""

        guard cursor < plan.count else {
            step = .finished
            return
        }

        switch plan[cursor] {
        case .present(let id):
            guard let word = currentWord(id) else { cursor += 1; advance(); return }
            // If it's no longer new (e.g. requeued state), skip the intro.
            guard word.isNew else { cursor += 1; advance(); return }
            step = .flashcard(word)

        case .quiz(let id, let kind):
            guard let word = currentWord(id) else { cursor += 1; advance(); return }
            switch kind {
            case .multipleChoice: step = .multipleChoice(word: word, options: makeOptions(for: word))
            case .reversedChoice: step = .reversedChoice(word: word, options: makeMeaningOptions(for: word))
            case .audioChoice:    step = .audioChoice(word: word, options: makeMeaningOptions(for: word))
            case .typing:         step = .typing(word)
            case .audioTyping:    step = .audioTyping(word)
            case .tapping:        step = .tapping(word: word, tokens: makeTokens(for: word))
            case .fillBlank:
                // Only when the word truly appears in its example; otherwise a
                // plain typing recall (so the plan slot is never wasted).
                if let blank = Self.blankable(for: word) {
                    step = .fillBlank(word: word, sentence: blank.sentence, answer: blank.answer)
                } else {
                    step = .typing(word)
                }
            }
        }
    }

    // MARK: - Fill-in-the-blank

    private static let blankToken = "_____"

    /// If `word` (or its verb stem after a leading "to ") appears as a whole word
    /// in its own example sentence, returns the sentence with that occurrence
    /// blanked out plus the exact text removed (the expected answer). Returns nil
    /// when there's no example or no clean whole-word match — the caller then
    /// falls back to a plain typing question.
    static func blankable(for word: DeckWord) -> (sentence: String, answer: String)? {
        let example = word.example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !example.isEmpty else { return nil }

        // Surface forms to look for. A verb stored as "to deploy" usually appears
        // as "deploy" in the sentence, so try the stem too. Longest first, so a
        // full phrase ("pull request") wins over any shorter stem.
        var candidates = [word.word]
        if word.word.lowercased().hasPrefix("to ") {
            candidates.append(String(word.word.dropFirst(3)))
        }
        candidates = candidates
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for candidate in candidates {
            guard let range = wholeWordRange(of: candidate, in: example) else { continue }
            let answer = String(example[range])
            let blanked = example.replacingCharacters(in: range, with: blankToken)
            return (blanked, answer)
        }
        return nil
    }

    /// Case-insensitive search for `needle` as a whole word/phrase (bounded by
    /// word boundaries) in `haystack`.
    private static func wholeWordRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(haystack.startIndex..., in: haystack)
        guard let match = regex.firstMatch(in: haystack, range: nsRange),
              let range = Range(match.range, in: haystack) else { return nil }
        return range
    }

    private func currentWord(_ id: UUID) -> DeckWord? {
        store.deck(id: deckID)?.words.first { $0.id == id }
    }

    /// Builds 4 options (1 correct + 3 distinct wrong) from the deck.
    private func makeOptions(for word: DeckWord) -> [String] {
        let others = (store.deck(id: deckID)?.words ?? [])
            .filter { $0.id != word.id }
            .map(\.word)
        var options = Array(Set(others)).shuffled().prefix(3).map { $0 }
        options.append(word.word)
        // Pad if the deck is tiny (< 4 words).
        let fillers = ["meeting", "deadline", "feature", "release", "ticket"]
        var i = 0
        while options.count < 4 {
            let f = fillers[i % fillers.count]; i += 1
            if !options.contains(f) { options.append(f) }
        }
        return options.shuffled()
    }

    /// 4 Vietnamese-meaning options for the audio quiz (1 correct + 3 wrong).
    private func makeMeaningOptions(for word: DeckWord) -> [String] {
        let others = (store.deck(id: deckID)?.words ?? [])
            .filter { $0.id != word.id }
            .map(\.meaning)
        var options = Array(Set(others)).shuffled().prefix(3).map { $0 }
        options.append(word.meaning)
        let fillers = ["cuộc họp", "thời hạn", "tính năng", "bản phát hành", "phiếu việc"]
        var i = 0
        while options.count < 4 {
            let f = fillers[i % fillers.count]; i += 1
            if !options.contains(f) { options.append(f) }
        }
        return options.shuffled()
    }

    /// Word tokens (correct + distractor) for the tapping exercise, shuffled.
    private func makeTokens(for word: DeckWord) -> [String] {
        let correct = word.word.split(separator: " ").map(String.init)
        let others = (store.deck(id: deckID)?.words ?? [])
            .filter { $0.id != word.id }
            .flatMap { $0.word.split(separator: " ").map(String.init) }
        let distractors = Array(Set(others).subtracting(correct)).shuffled().prefix(3)
        return (correct + distractors).shuffled()
    }

    // MARK: - User actions

    /// Flashcard "Next": introduce the word (0 → 1) and move on. The word's
    /// quizzes are already scheduled later in the plan for this batch.
    func flashcardNext() {
        guard case let .flashcard(word) = step else { return }
        var w = word
        w.correctCount = 1            // introduced → now "learning"
        save(w)
        cursor += 1
        advance()
    }

    /// Multiple-choice answer (English word).
    func answerMultipleChoice(_ choice: String) {
        guard case let .multipleChoice(word, _) = step else { return }
        grade(word: word, isCorrect: choice == word.word)
    }

    /// Reversed multiple-choice answer (Vietnamese meaning for an English word).
    func answerReversedChoice(_ choice: String) {
        guard case let .reversedChoice(word, _) = step else { return }
        grade(word: word, isCorrect: choice == word.meaning)
    }

    /// Audio quiz answer (Vietnamese meaning).
    func answerAudioChoice(_ choice: String) {
        guard case let .audioChoice(word, _) = step else { return }
        grade(word: word, isCorrect: choice == word.meaning)
    }

    /// Tapping answer — the assembled phrase (case/space-insensitive match).
    func answerTapping(_ assembled: String) {
        guard case let .tapping(word, _) = step else { return }
        func norm(_ s: String) -> String {
            s.lowercased().split(separator: " ").joined(separator: " ")
        }
        grade(word: word, isCorrect: norm(assembled) == norm(word.word))
    }

    /// Typing answer (case/whitespace-insensitive exact match).
    func answerTyping(_ text: String) {
        guard case let .typing(word) = step else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = word.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        grade(word: word, isCorrect: normalized == target)
    }

    /// Dictation answer — same matching as typing, but the prompt was audio only.
    func answerAudioTyping(_ text: String) {
        guard case let .audioTyping(word) = step else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = word.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        grade(word: word, isCorrect: normalized == target)
    }

    /// Fill-in-the-blank answer — match against the exact text removed from the
    /// example (case/whitespace-insensitive).
    func answerFillBlank(_ text: String) {
        guard case let .fillBlank(word, _, answer) = step else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        grade(word: word, isCorrect: normalized == target)
    }

    /// Move on after the feedback overlay (called by the view's Continue).
    func continueAfterFeedback() {
        handleRequeue()
        cursor += 1
        advance()
    }

    // MARK: - Grading

    private func grade(word: DeckWord, isCorrect: Bool) {
        guard let live = currentWord(word.id) else { return }
        var w = live
        answeredCount += 1
        revealedAnswer = w.word

        if isCorrect {
            feedback = .correct
            correctThisSession += 1

            if w.isMastered {
                // A correct review → grow the interval.
                let next = Self.nextInterval(after: w.intervalDays)
                w.intervalDays = next
                w.nextReviewDate = Calendar.current.date(byAdding: .day, value: next, to: .now)
            } else {
                w.correctCount += 1
                if w.correctCount >= DeckWord.masteryGoal {
                    // Just mastered → first review in 1 day.
                    w.intervalDays = 1
                    w.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
                }
            }
        } else {
            feedback = .incorrect
            w.correctCount = 0
            w.intervalDays = 0
            w.nextReviewDate = nil
        }
        lastWord = w        // post-answer snapshot → growth badge shows new count
        save(w)
    }

    /// After a miss, schedule one extra quiz for the word later in the session.
    private func handleRequeue() {
        guard feedback == .incorrect, let id = lastWord?.id, !retried.contains(id) else { return }
        retried.insert(id)
        // Insert a few steps ahead (not immediately) so it comes back spaced out.
        let insertAt = min(plan.count, cursor + 3)
        plan.insert(.quiz(id, .typing), at: insertAt)
    }

    private func save(_ word: DeckWord) {
        store.update(word, inDeck: deckID)
    }

    // MARK: - Interval progression: 1 → 3 → 7 → 14 → ×2

    static func nextInterval(after current: Int) -> Int {
        switch current {
        case ..<1: return 1
        case 1:    return 3
        case 3:    return 7
        case 7:    return 14
        default:   return current * 2
        }
    }
}
