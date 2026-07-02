//
//  GrammarModels.swift
//  ITBizEnglish
//
//  AI Grammar Lessons: the user types a grammar pattern (e.g. "I'm getting…",
//  "Used to", "Be going to") plus optional learning requests, and the AI returns
//  a full Duolingo-style lesson — broken into bite-size cards (hero, meaning,
//  structure, a visual chain, real-life usage, collocations, common mistakes, a
//  comparison) followed by a 10-step practice and a 30-second summary.
//
//  Everything here is Codable (the AI returns JSON matching this shape, and the
//  store persists saved lessons) and Hashable (so a lesson can drive value-based
//  `navigationDestination` for the "related grammar" one-click navigation).
//
//  Decoding is deliberately forgiving: a missing section falls back to an empty
//  one instead of failing the whole lesson, since LLM output can drop a field.
//

import Foundation
import SwiftUI

// MARK: - Difficulty

enum GrammarDifficulty: String, Codable, Hashable {
    case easy, medium, hard

    init(loose raw: String) {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "easy", "dễ", "de", "beginner":  self = .easy
        case "hard", "khó", "kho", "advanced": self = .hard
        default:                               self = .medium
        }
    }

    var label: String {
        switch self {
        case .easy:   return "Dễ"
        case .medium: return "Trung bình"
        case .hard:   return "Khó"
        }
    }
    var color: Color {
        switch self {
        case .easy:   return .duoGreen
        case .medium: return .duoGold
        case .hard:   return .duoRed
        }
    }
    var edge: Color {
        switch self {
        case .easy:   return .duoGreenEdge
        case .medium: return .duoGoldEdge
        case .hard:   return .duoRedEdge
        }
    }
}

// MARK: - Lesson sections

struct GrammarHero: Codable, Hashable {
    var pattern: String = ""
    var difficulty: String = "medium"
    var category: String = "Grammar"
    var time: String = "5–10 phút"
    var quickMeaning: String = ""
    var example: String = ""
    var exampleVi: String = ""

    var difficultyValue: GrammarDifficulty { GrammarDifficulty(loose: difficulty) }

    /// SF Symbol + tint for the category chip.
    var categoryIcon: String {
        switch category.lowercased() {
        case let c where c.contains("speak"): return "waveform"
        case let c where c.contains("writ"):  return "pencil.line"
        case let c where c.contains("dail"):  return "sun.max.fill"
        default:                              return "textformat.abc"
        }
    }
    var categoryColor: Color {
        switch category.lowercased() {
        case let c where c.contains("speak"): return .duoBlue
        case let c where c.contains("writ"):  return .duoIndigo
        case let c where c.contains("dail"):  return .duoGold
        default:                              return .duoGreen
        }
    }

    static let empty = GrammarHero()
}

struct GrammarMeaning: Codable, Hashable {
    var whatItMeans: String = ""
    var whenToUse: String = ""
    var whenNotToUse: String = ""
    static let empty = GrammarMeaning()
}

struct GrammarStructure: Codable, Hashable {
    var formula: [String] = []
    var examples: [String] = []
    static let empty = GrammarStructure()
}

struct GrammarVisual: Codable, Hashable {
    var title: String = ""
    var steps: [String] = []
    var caption: String = ""
    static let empty = GrammarVisual()
}

struct GrammarUsage: Codable, Hashable, Identifiable {
    var id = UUID()
    var context: String = ""
    var sentence: String = ""

    enum CodingKeys: String, CodingKey { case context, sentence }

    /// SF Symbol guessed from the situation label (Weather/Work/Travel…).
    var icon: String {
        let c = context.lowercased()
        if c.contains("weather") || c.contains("thời tiết") { return "cloud.sun.fill" }
        if c.contains("work") || c.contains("công việc") || c.contains("job") { return "briefcase.fill" }
        if c.contains("travel") || c.contains("du lịch") { return "airplane" }
        if c.contains("friend") || c.contains("bạn") { return "person.2.fill" }
        if c.contains("food") || c.contains("ăn") || c.contains("eat") { return "fork.knife" }
        if c.contains("health") || c.contains("sức khỏe") { return "heart.fill" }
        if c.contains("home") || c.contains("nhà") { return "house.fill" }
        return "bubble.left.and.bubble.right.fill"
    }
}

struct GrammarMistake: Codable, Hashable, Identifiable {
    var id = UUID()
    var wrong: String = ""
    var correct: String = ""
    var explanation: String = ""
    enum CodingKeys: String, CodingKey { case wrong, correct, explanation }
}

struct GrammarComparison: Codable, Hashable {
    var otherName: String = ""
    var thisLabel: String = ""
    var otherLabel: String = ""
    var rows: [Row] = []
    var summary: String = ""

    struct Row: Codable, Hashable, Identifiable {
        var id = UUID()
        var aspect: String = ""
        var thisValue: String = ""
        var otherValue: String = ""
        enum CodingKeys: String, CodingKey { case aspect, thisValue, otherValue }
    }
    static let empty = GrammarComparison()
}

// MARK: - Exercises

/// One practice item. A single flexible shape covers all 10 exercise kinds;
/// each renderer reads only the fields its `kind` needs. `id` is generated
/// locally (excluded from Codable) so SwiftUI can iterate stably.
struct GrammarExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: String = "multipleChoice"
    /// The question / instruction / source text shown at the top.
    var prompt: String = ""
    /// Options for the tap-to-choose kinds.
    var options: [String]? = nil
    /// Index into `options` of the correct answer.
    var answerIndex: Int? = nil
    /// Canonical correct sentence (word-order target / corrected version).
    var answer: String? = nil
    /// Pre-scrambled tokens for word-order (falls back to splitting `answer`).
    var words: [String]? = nil
    /// Why the answer is right / the underlying rule — shown in feedback.
    var explanation: String? = nil
    /// Extra one-line example reinforcing the point (shown in feedback).
    var example: String? = nil
    /// Optional Vietnamese gloss / source (for VN→EN, or a hint).
    var vietnamese: String? = nil

    enum CodingKeys: String, CodingKey {
        case type, prompt, options, answerIndex, answer, words, explanation, example, vietnamese
    }

    enum Kind: String, CaseIterable, Identifiable {
        case multipleChoice, fillBlank, wordOrder, enToVi, viToEn,
             chooseBetter, findMistake, conversation, writeSentence, miniChallenge
        var id: String { rawValue }

        /// Short Vietnamese label for the exercise-type picker.
        var label: String {
            switch self {
            case .multipleChoice: return "Trắc nghiệm nghĩa"
            case .fillBlank:      return "Điền chỗ trống"
            case .wordOrder:      return "Sắp xếp câu"
            case .enToVi:         return "Dịch Anh → Việt"
            case .viToEn:         return "Dịch Việt → Anh"
            case .chooseBetter:   return "Chọn câu hay hơn"
            case .findMistake:    return "Tìm lỗi sai"
            case .conversation:   return "Hoàn thành hội thoại"
            case .writeSentence:  return "Tự viết câu"
            case .miniChallenge:  return "Thử thách viết"
            }
        }
        var icon: String {
            switch self {
            case .multipleChoice: return "list.bullet"
            case .fillBlank:      return "square.dashed"
            case .wordOrder:      return "arrow.left.arrow.right"
            case .enToVi:         return "character.book.closed"
            case .viToEn:         return "text.bubble"
            case .chooseBetter:   return "checkmark.seal"
            case .findMistake:    return "magnifyingglass"
            case .conversation:   return "bubble.left.and.bubble.right"
            case .writeSentence:  return "pencil"
            case .miniChallenge:  return "flag.checkered"
            }
        }
    }
    var kind: Kind { Kind(rawValue: type) ?? .multipleChoice }

    /// Open-ended kinds are graded by the AI rather than matched locally.
    var isOpenEnded: Bool { kind == .writeSentence || kind == .miniChallenge }

    /// Tokens to arrange for word-order kinds (uses `words`, else splits answer).
    var arrangeTokens: [String] {
        if let words, !words.isEmpty { return words }
        return (answer ?? "").split(separator: " ").map(String.init)
    }

    /// Short human label used on the exercise progress chrome.
    var kindLabel: String { kind.label }

    // MARK: - Structural validation

    /// Kinds that present tap-to-choose options graded by `answerIndex`.
    var usesOptions: Bool {
        switch kind {
        case .multipleChoice, .fillBlank, .enToVi, .chooseBetter, .findMistake, .conversation:
            return true
        default:
            return false
        }
    }

    /// Kinds where the learner arranges word tiles into `answer`.
    var usesArrange: Bool {
        switch kind {
        case .wordOrder, .viToEn: return true
        default: return false
        }
    }

    /// Normalized, sorted word tokens — used to check that arrange tiles can
    /// actually recompose the answer (order-independent multiset compare).
    static func normalizedTokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// True when this exercise is well-formed enough to present AND auto-grade
    /// correctly. (Equivalent to `sanitized() != nil`.)
    var isStructurallyValid: Bool { sanitized() != nil }

    /// Returns a cleaned copy that is safe to show, or `nil` if the item is
    /// unsalvageable and should be dropped. This is the first line of defense
    /// against malformed LLM output being presented as a graded question:
    ///
    /// - Any kind: must have a non-empty prompt.
    /// - Option kinds: need ≥2 non-empty options and an `answerIndex` in range —
    ///   otherwise the "correct" answer is unknown, so the item is dropped.
    /// - Arrange kinds: need a non-empty `answer`; `words` are repaired so they
    ///   truly recompose the answer (rebuilt from the answer when they don't),
    ///   guaranteeing the tile puzzle is always solvable.
    /// - Open-ended kinds: only need a prompt (the AI grades the free text).
    func sanitized() -> GrammarExercise? {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return nil }

        var ex = self
        ex.prompt = cleanPrompt

        if isOpenEnded { return ex }

        if usesOptions {
            let opts = (options ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard opts.count >= 2, let idx = answerIndex, opts.indices.contains(idx) else { return nil }
            ex.options = opts
            return ex
        }

        if usesArrange {
            let ans = (answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ans.isEmpty else { return nil }
            ex.answer = ans
            let provided = (words ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if provided.isEmpty || Self.normalizedTokens(provided.joined(separator: " ")) != Self.normalizedTokens(ans) {
                ex.words = ans.split(separator: " ").map(String.init)   // rebuild solvable tiles
            } else {
                ex.words = provided
            }
            return ex
        }

        return ex
    }
}

extension Array where Element == GrammarExercise {
    /// Drops/repairs malformed exercises, preserving order.
    func sanitized() -> [GrammarExercise] { compactMap { $0.sanitized() } }
}

struct GrammarSummary: Codable, Hashable {
    var meaning: String = ""
    var structure: String = ""
    var keyTip: String = ""
    var commonMistake: String = ""
    var phrases: [String] = []
    static let empty = GrammarSummary()
}

struct GrammarFlashcard: Codable, Hashable, Identifiable {
    var id = UUID()
    var front: String = ""
    var meaning: String = ""
    var formula: String = ""
    var example: String = ""
    enum CodingKeys: String, CodingKey { case front, meaning, formula, example }
}

// MARK: - The lesson

struct GrammarLesson: Codable, Hashable {
    var hero: GrammarHero = .empty
    var meaning: GrammarMeaning = .empty
    var structure: GrammarStructure = .empty
    var visual: GrammarVisual = .empty
    var usage: [GrammarUsage] = []
    var collocations: [String] = []
    var mistakes: [GrammarMistake] = []
    var comparison: GrammarComparison = .empty
    var exercises: [GrammarExercise] = []
    var summary: GrammarSummary = .empty
    var flashcards: [GrammarFlashcard] = []
    var relatedGrammar: [String] = []

    enum CodingKeys: String, CodingKey {
        case hero, meaning, structure, visual, usage, collocations,
             mistakes, comparison, exercises, summary, flashcards, relatedGrammar
    }

    init() {}

    /// Forgiving decode: each section falls back to empty rather than throwing,
    /// so a lesson still renders if the model omits or malforms one field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hero          = (try? c.decode(GrammarHero.self, forKey: .hero)) ?? .empty
        meaning       = (try? c.decode(GrammarMeaning.self, forKey: .meaning)) ?? .empty
        structure     = (try? c.decode(GrammarStructure.self, forKey: .structure)) ?? .empty
        visual        = (try? c.decode(GrammarVisual.self, forKey: .visual)) ?? .empty
        usage         = (try? c.decode([GrammarUsage].self, forKey: .usage)) ?? []
        collocations  = (try? c.decode([String].self, forKey: .collocations)) ?? []
        mistakes      = (try? c.decode([GrammarMistake].self, forKey: .mistakes)) ?? []
        comparison    = (try? c.decode(GrammarComparison.self, forKey: .comparison)) ?? .empty
        exercises     = (try? c.decode([GrammarExercise].self, forKey: .exercises)) ?? []
        summary       = (try? c.decode(GrammarSummary.self, forKey: .summary)) ?? .empty
        flashcards    = (try? c.decode([GrammarFlashcard].self, forKey: .flashcards)) ?? []
        relatedGrammar = (try? c.decode([String].self, forKey: .relatedGrammar)) ?? []
    }

    /// Has enough content to be worth showing.
    var isUsable: Bool { !hero.pattern.isEmpty || !meaning.whatItMeans.isEmpty }
}

// MARK: - Saved lesson + spaced repetition

/// A batch of practice exercises the user generated for a chosen context, kept
/// on the lesson so it can be re-run later without re-calling the AI.
struct SavedExerciseSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var contextLabel: String
    var exercises: [GrammarExercise]
    var createdAt: Date = .now
    var bestScore: Int? = nil

    enum CodingKeys: String, CodingKey { case id, contextLabel, exercises, createdAt, bestScore }
    init(contextLabel: String, exercises: [GrammarExercise]) {
        self.contextLabel = contextLabel
        self.exercises = exercises
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        contextLabel = try c.decodeIfPresent(String.self, forKey: .contextLabel) ?? ""
        exercises = try c.decodeIfPresent([GrammarExercise].self, forKey: .exercises) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore)
    }
}

/// A lesson the user saved to review later, with a simple spaced-repetition
/// schedule (review after 1 → 3 → 7 → 14 → 30 days as it's re-reviewed).
struct SavedGrammarLesson: Codable, Identifiable, Hashable {
    var id = UUID()
    var pattern: String
    var request: String = ""
    var lesson: GrammarLesson
    var createdAt: Date = .now
    /// Best practice score so far (0…100), nil until practiced.
    var bestScore: Int? = nil
    /// How many times it's been reviewed — indexes into `Self.intervals`.
    var reviewStage: Int = 0
    var nextReviewAt: Date = .now
    /// AI-generated practice sets the user made for this lesson (newest first).
    var exerciseSets: [SavedExerciseSet] = []

    /// Days until the next review at each stage.
    static let intervals: [Int] = [1, 3, 7, 14, 30]

    enum CodingKeys: String, CodingKey {
        case id, pattern, request, lesson, createdAt, bestScore, reviewStage, nextReviewAt, exerciseSets
    }
    init(id: UUID = UUID(), pattern: String, request: String, lesson: GrammarLesson,
         createdAt: Date = .now, bestScore: Int? = nil) {
        self.id = id
        self.pattern = pattern
        self.request = request
        self.lesson = lesson
        self.createdAt = createdAt
        self.bestScore = bestScore
        self.reviewStage = 0
        self.nextReviewAt = Self.date(afterDays: Self.intervals[0])
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self, forKey: .id)
        pattern     = try c.decode(String.self, forKey: .pattern)
        request     = try c.decodeIfPresent(String.self, forKey: .request) ?? ""
        lesson      = try c.decode(GrammarLesson.self, forKey: .lesson)
        createdAt   = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        bestScore   = try c.decodeIfPresent(Int.self, forKey: .bestScore)
        reviewStage = try c.decodeIfPresent(Int.self, forKey: .reviewStage) ?? 0
        nextReviewAt = try c.decodeIfPresent(Date.self, forKey: .nextReviewAt) ?? .now
        exerciseSets = try c.decodeIfPresent([SavedExerciseSet].self, forKey: .exerciseSets) ?? []
    }

    var isDue: Bool { nextReviewAt <= Date() }

    /// Friendly "review tomorrow / in 3 days / in 7 days" copy for the current stage.
    var nextReviewLabel: String {
        let days = Self.intervals[min(reviewStage, Self.intervals.count - 1)]
        switch days {
        case 1:  return "Ôn lại vào ngày mai"
        case 3:  return "Ôn lại sau 3 ngày"
        case 7:  return "Ôn lại sau 1 tuần"
        case 14: return "Ôn lại sau 2 tuần"
        default: return "Ôn lại sau \(days) ngày"
        }
    }

    static func date(afterDays days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }
}

// MARK: - Navigation route

/// Carries a generated/saved lesson into `navigationDestination`, so "related
/// grammar" chips can push a fresh lesson onto the same stack with one tap.
struct GrammarRoute: Identifiable, Hashable {
    var id = UUID()
    var pattern: String
    var request: String
    var lesson: GrammarLesson
    /// Set when opened from a saved lesson (so practice updates its score).
    var savedID: UUID? = nil
}

// MARK: - Mistakes bank

/// One grammar question the learner got wrong, kept so it can be re-drilled
/// later (error-driven retrieval practice). Stores the full, already-sanitized
/// exercise so the review can render and grade it exactly like the first time.
struct GrammarMistakeEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    /// The grammar pattern the mistake came from (for grouping/display).
    var pattern: String = ""
    /// Where it happened, e.g. "Bài học", "IT / Lập trình" (the practice context).
    var sourceLabel: String = ""
    /// The missed exercise (sanitized), replayable in the review runner.
    var exercise: GrammarExercise = GrammarExercise()
    /// What the learner answered (for their reference), may be empty.
    var userAnswer: String = ""
    var date: Date = .now
    /// How many times this exact question has been missed.
    var timesWrong: Int = 1

    enum CodingKeys: String, CodingKey {
        case id, pattern, sourceLabel, exercise, userAnswer, date, timesWrong
    }

    init(id: UUID = UUID(), pattern: String, sourceLabel: String,
         exercise: GrammarExercise, userAnswer: String = "",
         date: Date = .now, timesWrong: Int = 1) {
        self.id = id
        self.pattern = pattern
        self.sourceLabel = sourceLabel
        self.exercise = exercise
        self.userAnswer = userAnswer
        self.date = date
        self.timesWrong = timesWrong
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        sourceLabel = try c.decodeIfPresent(String.self, forKey: .sourceLabel) ?? ""
        exercise = try c.decodeIfPresent(GrammarExercise.self, forKey: .exercise) ?? GrammarExercise()
        userAnswer = try c.decodeIfPresent(String.self, forKey: .userAnswer) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        timesWrong = try c.decodeIfPresent(Int.self, forKey: .timesWrong) ?? 1
    }

    /// Identity of the *question* (independent of pattern), used to dedupe and
    /// to resolve an entry when the learner finally answers it correctly.
    var questionKey: String {
        (exercise.type + "␟" + exercise.prompt)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Lesson feedback

/// A learner's rating of a generated lesson. Negative feedback carries reasons
/// that can be fed back into a regeneration to fix the specific complaint.
struct GrammarLessonFeedback: Codable, Identifiable, Hashable {
    var id = UUID()
    var pattern: String = ""
    var positive: Bool = false
    var reasons: [String] = []
    var note: String = ""
    var date: Date = .now

    enum CodingKeys: String, CodingKey { case id, pattern, positive, reasons, note, date }

    init(id: UUID = UUID(), pattern: String, positive: Bool,
         reasons: [String] = [], note: String = "", date: Date = .now) {
        self.id = id
        self.pattern = pattern
        self.positive = positive
        self.reasons = reasons
        self.note = note
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        positive = try c.decodeIfPresent(Bool.self, forKey: .positive) ?? false
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
    }
}
