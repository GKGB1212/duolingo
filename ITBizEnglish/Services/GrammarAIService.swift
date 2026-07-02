//
//  GrammarAIService.swift
//  ITBizEnglish
//
//  Turns a grammar pattern (+ optional learning requests) into a full
//  Duolingo-style lesson as structured JSON, and grades the open-ended practice
//  answers. Also holds GrammarStore — the persisted list of saved lessons with
//  their spaced-repetition schedule (kept here, next to the models it serves,
//  like ChatHistoryStore lives beside ChatAIService).
//
//  All networking goes through the shared LLMClient so provider rotation and
//  failover are handled in one place.
//

import Foundation
import Observation

struct GrammarAIService {

    // MARK: - Lesson generation

    private let systemPrompt = """
    You are an outstanding, friendly English teacher building a GAMIFIED, Duolingo-style grammar lesson for a Vietnamese learner. You do NOT write articles or textbook definitions. You design a lesson made of small, punchy cards — one idea per card, minimal text, lots of real-life examples.

    HARD RULES:
    - Every explanation, label, hint and mistake-explanation is in natural, simple VIETNAMESE.
    - All target-language content (examples, collocations, the formula tokens, English options) is in ENGLISH.
    - Keep every text SHORT. No paragraphs. Friendly, encouraging tone. No grammar jargon when avoidable.
    - Be practical and real-life. Make it DIFFERENT and fresh every time. Never copy dictionary definitions.
    - Personalize to the user's optional request if given.

    Respond with ONLY a raw JSON object (no markdown fences, no extra text) of EXACTLY this shape:
    {
      "hero": {
        "pattern": "the grammar pattern, cleaned up",
        "difficulty": "easy" | "medium" | "hard",
        "category": "Grammar" | "Speaking" | "Writing" | "Daily English",
        "time": "5–10 phút",
        "quickMeaning": "ONE short Vietnamese sentence: what this is for",
        "example": "one natural highlighted English example sentence",
        "exampleVi": "its Vietnamese translation"
      },
      "meaning": {
        "whatItMeans": "1 short Vietnamese sentence",
        "whenToUse": "1 short Vietnamese sentence: when natives use it",
        "whenNotToUse": "1 short Vietnamese sentence: when NOT to use it"
      },
      "structure": {
        "formula": ["Subject","am/is/are","getting","adjective"],
        "examples": ["3 short natural English example sentences"]
      },
      "visual": {
        "title": "short Vietnamese title of the idea",
        "steps": ["Happy","Getting happier","Very happy"],
        "caption": "1 short Vietnamese line tying the chain together"
      },
      "usage": [
        {"context":"Weather","sentence":"one short English sentence"}
        // EXACTLY 5 varied real-life situations (e.g. Weather, Work, Travel, Friends, Daily conversation)
      ],
      "collocations": ["getting hungry","getting tired", "... 12 to 15 common English collocations/phrases"],
      "mistakes": [
        {"wrong":"❌ wrong English sentence","correct":"✅ correct English sentence","explanation":"short Vietnamese why"}
        // EXACTLY 5
      ],
      "comparison": {
        "otherName":"the similar grammar to compare with (e.g. becoming)",
        "thisLabel":"short label for THIS grammar",
        "otherLabel":"short label for the OTHER grammar",
        "rows":[{"aspect":"Vietnamese aspect","thisValue":"English/short","otherValue":"English/short"}],
        "summary":"1 short Vietnamese takeaway"
      },
      "exercises": [
        // EXACTLY 10 items, increasing difficulty, in THIS order and with these "type" values & fields:
        // 1 {"type":"multipleChoice","prompt":"Vietnamese question about meaning","options":["A","B","C"],"answerIndex":0,"explanation":"Vietnamese","example":"English"}
        // 2 {"type":"fillBlank","prompt":"English sentence with a ___ blank","options":["word1","word2","word3"],"answerIndex":1,"explanation":"Vietnamese","example":"English"}
        // 3 {"type":"wordOrder","prompt":"Vietnamese instruction","answer":"the correct English sentence","words":["scrambled","tokens"],"explanation":"Vietnamese"}
        // 4 {"type":"enToVi","prompt":"an English sentence","options":["Vietnamese A","Vietnamese B","Vietnamese C"],"answerIndex":0,"explanation":"Vietnamese"}
        // 5 {"type":"viToEn","prompt":"a Vietnamese sentence","answer":"the correct English sentence","words":["scrambled","english","tokens"],"explanation":"Vietnamese"}
        // 6 {"type":"chooseBetter","prompt":"Vietnamese instruction","options":["English option A","English option B"],"answerIndex":0,"explanation":"Vietnamese why the chosen one is more natural"}
        // 7 {"type":"findMistake","prompt":"an English sentence containing ONE mistake","options":["candidate wrong part 1","part 2","part 3"],"answerIndex":2,"answer":"the fully corrected English sentence","explanation":"Vietnamese"}
        // 8 {"type":"conversation","prompt":"A: ...\\nB: ___","options":["English reply A","English reply B","English reply C"],"answerIndex":0,"explanation":"Vietnamese"}
        // 9 {"type":"writeSentence","prompt":"Vietnamese instruction to write ONE English sentence using the grammar","vietnamese":"optional Vietnamese sentence to translate, or empty"}
        // 10 {"type":"miniChallenge","prompt":"Vietnamese instruction to write 3 original English sentences using the grammar"}
      ],
      "summary": {
        "meaning":"1 short Vietnamese line",
        "structure":"the formula as a short string",
        "keyTip":"1 short Vietnamese tip",
        "commonMistake":"1 short Vietnamese mistake to avoid",
        "phrases":["3 short English example phrases"]
      },
      "relatedGrammar": ["4 to 6 related grammar patterns the learner could study next"]
    }
    """

    /// Generates the full lesson for `pattern`, personalized by `request`.
    func generate(pattern: String, request: String) async throws -> GrammarLesson {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw TranslationError.emptyInput }

        var userText = "Grammar pattern to teach: \"\(p)\"."
        let r = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty {
            userText += "\nLearner's extra request (personalize the whole lesson to this): \(r)"
        }
        userText += "\nBuild the complete Duolingo-style lesson JSON now."

        // Lower temperature than before: the same call produces the answer keys,
        // so less randomness means more reliable "correct" answers (variety still
        // comes from the "make it fresh every time" instruction + related grammar).
        let content = try await LLMClient.generateJSON(system: systemPrompt, user: userText, temperature: 0.6)
        guard let data = content.data(using: .utf8),
              var lesson = try? JSONDecoder().decode(GrammarLesson.self, from: data),
              lesson.isUsable else {
            throw TranslationError.decoding
        }
        // Validate (and optionally AI-verify) exercises before they can be shown.
        lesson.exercises = await sanitizeAndVerify(pattern: p, exercises: lesson.exercises)
        return lesson
    }

    // MARK: - Fresh practice set for a chosen context

    private let exercisesSystemPrompt = """
    You create a FRESH, varied set of Duolingo-style practice exercises for a Vietnamese learner drilling ONE grammar pattern, all set in a chosen real-life CONTEXT/topic.
    Rules: Vietnamese for every instruction/explanation/hint; English for target-language content. Keep every text SHORT. Increasing difficulty. Make them different every time and clearly tied to the context.
    Respond with ONLY a raw JSON object {"exercises":[ ... ]}. Mix these "type" values & fields:
    - {"type":"multipleChoice","prompt":"Vietnamese question","options":["A","B","C"],"answerIndex":0,"explanation":"Vietnamese","example":"English"}
    - {"type":"fillBlank","prompt":"English sentence with a ___ blank","options":["w1","w2","w3"],"answerIndex":1,"explanation":"Vietnamese","example":"English"}
    - {"type":"wordOrder","prompt":"Vietnamese instruction","answer":"correct English sentence","words":["scrambled","tokens"],"explanation":"Vietnamese"}
    - {"type":"enToVi","prompt":"an English sentence","options":["VN A","VN B","VN C"],"answerIndex":0,"explanation":"Vietnamese"}
    - {"type":"viToEn","prompt":"a Vietnamese sentence","answer":"correct English sentence","words":["scrambled","tokens"],"explanation":"Vietnamese"}
    - {"type":"chooseBetter","prompt":"Vietnamese instruction","options":["English A","English B"],"answerIndex":0,"explanation":"Vietnamese"}
    - {"type":"findMistake","prompt":"English sentence with ONE mistake","options":["part1","part2","part3"],"answerIndex":2,"answer":"corrected sentence","explanation":"Vietnamese"}
    - {"type":"conversation","prompt":"A: ...\\nB: ___","options":["reply A","reply B","reply C"],"answerIndex":0,"explanation":"Vietnamese"}
    - {"type":"writeSentence","prompt":"Vietnamese instruction to write ONE English sentence in this context","vietnamese":"optional Vietnamese sentence to translate"}
    - {"type":"miniChallenge","prompt":"Vietnamese instruction to write 2-3 original English sentences in this context"}
    """

    /// Generates a fresh set of `count` exercises for `pattern` in the given
    /// real-life `context` (e.g. "công việc IT", "du lịch"), limited to the
    /// exercise `types` the user picked (empty = any type).
    func generateExercises(pattern: String, context: String,
                           types: [String], count: Int) async throws -> [GrammarExercise] {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw TranslationError.emptyInput }
        let n = min(max(count, 3), 12)

        var userText = """
        Grammar pattern: "\(p)".
        Context/topic for ALL exercises: \(ctx.isEmpty ? "general everyday English" : ctx).
        Generate \(n) fresh exercises tied to this context.
        """
        if !types.isEmpty {
            userText += "\nUse ONLY these exercise \"type\" values (spread them across the \(n) items): \(types.joined(separator: ", "))."
        }
        let content = try await LLMClient.generateJSON(system: exercisesSystemPrompt, user: userText, temperature: 0.55)
        guard let data = content.data(using: .utf8),
              let ex = try? JSONDecoder().decode(ExercisesWrapper.self, from: data).exercises,
              !ex.isEmpty else {
            throw TranslationError.decoding
        }
        let checked = await sanitizeAndVerify(pattern: p, exercises: ex)
        guard !checked.isEmpty else { throw TranslationError.decoding }
        return checked
    }

    private struct ExercisesWrapper: Decodable { let exercises: [GrammarExercise] }

    // MARK: - Exercise validation & verification

    /// Always structurally sanitizes exercises (dropping/repairing malformed
    /// items); then, when the user has answer-key verification enabled and there
    /// are objective items, runs a low-temperature AI check. Best-effort: the
    /// verification pass never blocks a lesson — any failure returns the
    /// structurally-clean set.
    private func sanitizeAndVerify(pattern: String, exercises: [GrammarExercise]) async -> [GrammarExercise] {
        let cleaned = exercises.sanitized()
        guard AppSettings.shared.verifyGrammar,
              cleaned.contains(where: { !$0.isOpenEnded }) else { return cleaned }
        return await verify(pattern: pattern, exercises: cleaned)
    }

    private let verifySystemPrompt = """
    You are a meticulous English teacher and test editor. You are given a JSON array of grammar practice exercises for a Vietnamese learner. Your ONLY job is to make sure each item's ANSWER KEY is correct and its English is natural — you are proof-reading, not rewriting.

    Rules:
    - Keep the SAME number of items in the SAME order, each with the SAME "type".
    - For option-based items (multipleChoice, fillBlank, enToVi, chooseBetter, findMistake, conversation): set "answerIndex" to the 0-based index of the genuinely correct option. If an option's English is wrong or unnatural, you may fix that option's text, but keep the same number of options.
    - For word-order items (wordOrder, viToEn): set "answer" to the correct, natural English sentence and "words" to that sentence's tokens.
    - Fix "explanation" only if it is factually wrong (keep it short, in Vietnamese).
    - Leave writeSentence and miniChallenge items unchanged.
    - Keep Vietnamese text in Vietnamese and English text in English. Do NOT invent new exercise types.
    - If an item is broken beyond repair, add "drop": true to it.

    Respond with ONLY a raw JSON object {"exercises":[ ... ]}. No markdown fences, no extra text.
    """

    /// Runs the low-temperature answer-key verification pass. Returns the
    /// corrected, re-sanitized set, or the input unchanged on any problem.
    func verify(pattern: String, exercises: [GrammarExercise]) async -> [GrammarExercise] {
        guard exercises.contains(where: { !$0.isOpenEnded }) else { return exercises }
        guard let payload = try? JSONEncoder().encode(VerifyExercisesWrapper(exercises: exercises)),
              let json = String(data: payload, encoding: .utf8) else { return exercises }

        let userText = """
        Grammar pattern being taught: "\(pattern)".
        Exercises JSON to verify (keep the order and the count exactly):
        \(json)
        Return the corrected {"exercises":[...]} now.
        """
        do {
            let content = try await LLMClient.generateJSON(system: verifySystemPrompt, user: userText, temperature: 0.15)
            guard let data = content.data(using: .utf8),
                  let out = try? JSONDecoder().decode(VerifyCorrectionsWrapper.self, from: data),
                  out.exercises.count == exercises.count else {
                return exercises
            }
            var result: [GrammarExercise] = []
            for (orig, corr) in zip(exercises, out.exercises) {
                if corr.drop == true { continue }
                if orig.isOpenEnded { result.append(orig); continue }
                var merged = orig
                if let idx = corr.answerIndex { merged.answerIndex = idx }
                if let a = corr.answer, !a.trimmingCharacters(in: .whitespaces).isEmpty { merged.answer = a }
                if let o = corr.options, o.count >= 2 { merged.options = o }
                if let w = corr.words, !w.isEmpty { merged.words = w }
                if let e = corr.explanation, !e.trimmingCharacters(in: .whitespaces).isEmpty { merged.explanation = e }
                if let clean = merged.sanitized() { result.append(clean) }
            }
            return result.isEmpty ? exercises : result
        } catch {
            return exercises
        }
    }

    private struct VerifyExercisesWrapper: Encodable { let exercises: [GrammarExercise] }
    private struct VerifyCorrectionsWrapper: Decodable { let exercises: [VerifyCorrection] }
    private struct VerifyCorrection: Decodable {
        let answerIndex: Int?
        let answer: String?
        let options: [String]?
        let words: [String]?
        let explanation: String?
        let drop: Bool?
    }

    // MARK: - Grading open-ended answers (Ex 9 & 10)

    private let evalSystemPrompt = """
    You are a warm, encouraging English teacher grading a Vietnamese learner's attempt to use a specific grammar pattern.
    Judge: correct use of the TARGET grammar, overall grammar, naturalness, and vocabulary.
    NEVER just say "wrong". Be specific and kind. Accept any natural phrasing.
    Do NOT deduct for capitalization or punctuation (treat it as spoken English).
    Respond with ONLY raw JSON (no markdown):
    {
      "score": 0-100 integer,
      "verdict": short label like "Tuyệt vời", "Tự nhiên", "Hiểu được", "Cần chỉnh",
      "correctedVersion": the best natural English version of what they tried to say,
      "notes": array of short SPECIFIC tips in Vietnamese (grammar rule + one more example), empty if already great
    }
    """

    /// Grades a free-written answer for a write-your-own / mini-challenge exercise.
    func evaluate(pattern: String, instruction: String, attempt: String) async throws -> AIFeedback {
        let a = attempt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { throw TranslationError.emptyInput }

        let userText = """
        Target grammar pattern: "\(pattern)"
        Task given to the learner: "\(instruction)"
        Learner's attempt: "\(a)"
        Grade it.
        """
        let content = try await LLMClient.generateJSON(system: evalSystemPrompt, user: userText, temperature: 0.3)
        guard let data = content.data(using: .utf8),
              let p = try? JSONDecoder().decode(EvalPayload.self, from: data) else {
            throw TranslationError.decoding
        }
        return AIFeedback(score: max(0, min(100, p.score)),
                          verdict: p.verdict,
                          correctedVersion: p.correctedVersion,
                          notes: p.notes)
    }

    private struct EvalPayload: Decodable {
        let score: Int
        let verdict: String
        let correctedVersion: String
        let notes: [String]
    }
}

// MARK: - Store

/// Source of truth for saved grammar lessons. Persists to a JSON file and keeps
/// each lesson's spaced-repetition schedule so the home screen can surface what's
/// due for review.
@Observable
final class GrammarStore {
    private(set) var lessons: [SavedGrammarLesson] = []
    /// Recently entered patterns (most recent first) for quick re-entry.
    private(set) var recentPatterns: [String] = []

    private let filename = "grammar.v1.json"
    private let recentsKey = "itbiz.grammar.recents.v1"

    init() {
        load()
        recentPatterns = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    // MARK: Saved lessons

    func saved(id: UUID) -> SavedGrammarLesson? { lessons.first { $0.id == id } }

    func contains(pattern: String) -> Bool {
        let key = pattern.lowercased().trimmingCharacters(in: .whitespaces)
        return lessons.contains { $0.pattern.lowercased().trimmingCharacters(in: .whitespaces) == key }
    }

    /// Saves a freshly generated lesson (or returns the existing one for the same
    /// pattern, refreshing its content). Returns the saved id.
    @discardableResult
    func save(_ lesson: GrammarLesson, pattern: String, request: String) -> UUID {
        let key = pattern.lowercased().trimmingCharacters(in: .whitespaces)
        if let i = lessons.firstIndex(where: { $0.pattern.lowercased().trimmingCharacters(in: .whitespaces) == key }) {
            lessons[i].lesson = lesson
            persist()
            return lessons[i].id
        }
        let entry = SavedGrammarLesson(pattern: pattern, request: request, lesson: lesson)
        lessons.insert(entry, at: 0)
        persist()
        return entry.id
    }

    func delete(id: UUID) {
        lessons.removeAll { $0.id == id }
        persist()
    }

    /// Records a practice score (keeps the best) for a saved lesson.
    func recordScore(_ score: Int, forSaved id: UUID) {
        guard let i = lessons.firstIndex(where: { $0.id == id }) else { return }
        lessons[i].bestScore = max(lessons[i].bestScore ?? 0, score)
        persist()
    }

    // MARK: Saved exercise sets

    /// Stores an AI-generated exercise set on a lesson (newest first) and returns
    /// its id so practice can record a score against it.
    @discardableResult
    func addExerciseSet(_ set: SavedExerciseSet, toSaved id: UUID) -> UUID {
        guard let i = lessons.firstIndex(where: { $0.id == id }) else { return set.id }
        lessons[i].exerciseSets.insert(set, at: 0)
        persist()
        return set.id
    }

    func recordExerciseSetScore(_ score: Int, setID: UUID, inSaved id: UUID) {
        guard let li = lessons.firstIndex(where: { $0.id == id }),
              let si = lessons[li].exerciseSets.firstIndex(where: { $0.id == setID }) else { return }
        lessons[li].exerciseSets[si].bestScore = max(lessons[li].exerciseSets[si].bestScore ?? 0, score)
        persist()
    }

    func deleteExerciseSet(setID: UUID, fromSaved id: UUID) {
        guard let li = lessons.firstIndex(where: { $0.id == id }) else { return }
        lessons[li].exerciseSets.removeAll { $0.id == setID }
        persist()
    }

    /// Records a spaced-repetition review outcome from an actual practice run.
    /// A pass advances the interval stage (review further out); a fail steps the
    /// stage back and re-schedules for tomorrow, so a shaky rule comes back soon.
    func recordReview(passed: Bool, forSaved id: UUID) {
        guard let i = lessons.firstIndex(where: { $0.id == id }) else { return }
        if passed {
            let next = min(lessons[i].reviewStage + 1, SavedGrammarLesson.intervals.count - 1)
            lessons[i].reviewStage = next
            lessons[i].nextReviewAt = SavedGrammarLesson.date(afterDays: SavedGrammarLesson.intervals[next])
        } else {
            lessons[i].reviewStage = max(0, lessons[i].reviewStage - 1)
            lessons[i].nextReviewAt = SavedGrammarLesson.date(afterDays: 1)
        }
        persist()
    }

    /// Marks a lesson reviewed: advances its spaced-repetition stage and schedules
    /// the next review.
    func markReviewed(id: UUID) {
        guard let i = lessons.firstIndex(where: { $0.id == id }) else { return }
        let next = min(lessons[i].reviewStage + 1, SavedGrammarLesson.intervals.count - 1)
        lessons[i].reviewStage = next
        lessons[i].nextReviewAt = SavedGrammarLesson.date(afterDays: SavedGrammarLesson.intervals[next])
        persist()
    }

    /// Lessons whose next-review date has arrived, soonest first.
    var dueForReview: [SavedGrammarLesson] {
        lessons.filter(\.isDue).sorted { $0.nextReviewAt < $1.nextReviewAt }
    }

    // MARK: Recents

    func rememberPattern(_ pattern: String) {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        recentPatterns.removeAll { $0.caseInsensitiveCompare(p) == .orderedSame }
        recentPatterns.insert(p, at: 0)
        if recentPatterns.count > 8 { recentPatterns = Array(recentPatterns.prefix(8)) }
        UserDefaults.standard.set(recentPatterns, forKey: recentsKey)
    }

    /// Replaces all saved lessons (used when importing a backup) and persists.
    func restore(_ lessons: [SavedGrammarLesson]) {
        self.lessons = lessons
        persist()
    }

    // MARK: Persistence

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(lessons) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedGrammarLesson].self, from: data) else { return }
        lessons = decoded
    }
}

// MARK: - Mistakes bank store

/// Persists grammar questions the learner got wrong so they can be re-drilled
/// later (error-driven retrieval practice). Same JSON-file pattern as the other
/// stores; newest first, deduped by question, capped so the file stays small.
@Observable
final class GrammarMistakeStore {
    private(set) var entries: [GrammarMistakeEntry] = []

    private let filename = "grammarMistakes.v1.json"
    private let cap = 300

    init() { load() }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    /// Records a missed question. If the same question is already banked, bumps
    /// its miss count and moves it to the front instead of duplicating.
    func record(pattern: String, sourceLabel: String, exercise: GrammarExercise, userAnswer: String = "") {
        guard let clean = exercise.sanitized() else { return }
        let entry = GrammarMistakeEntry(pattern: pattern, sourceLabel: sourceLabel,
                                        exercise: clean, userAnswer: userAnswer)
        if let i = entries.firstIndex(where: { $0.questionKey == entry.questionKey }) {
            var bumped = entries.remove(at: i)
            bumped.timesWrong += 1
            bumped.date = .now
            bumped.userAnswer = userAnswer
            entries.insert(bumped, at: 0)
        } else {
            entries.insert(entry, at: 0)
            if entries.count > cap { entries = Array(entries.prefix(cap)) }
        }
        persist()
    }

    /// Removes the banked entry for a question once it's finally answered right.
    func resolve(_ exercise: GrammarExercise) {
        let key = GrammarMistakeEntry(pattern: "", sourceLabel: "", exercise: exercise).questionKey
        let before = entries.count
        entries.removeAll { $0.questionKey == key }
        if entries.count != before { persist() }
    }

    func remove(id: UUID) { entries.removeAll { $0.id == id }; persist() }
    func remove(at offsets: IndexSet) { entries.remove(atOffsets: offsets); persist() }
    func clear() { entries.removeAll(); persist() }

    /// Missed exercises as a runnable practice set (newest first, fresh ids so
    /// the runner resets state cleanly per question).
    func practiceExercises(limit: Int = 20) -> [GrammarExercise] {
        entries.prefix(limit).map { entry in
            var ex = entry.exercise
            ex.id = UUID()
            return ex
        }
    }

    /// Entries grouped by grammar pattern, each group keeping newest-first order.
    var grouped: [(pattern: String, items: [GrammarMistakeEntry])] {
        var order: [String] = []
        var map: [String: [GrammarMistakeEntry]] = [:]
        for e in entries {
            let key = e.pattern.isEmpty ? "Khác" : e.pattern
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(e)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// Replaces all entries (used when importing a backup) and persists.
    func restore(_ entries: [GrammarMistakeEntry]) { self.entries = entries; persist() }

    // MARK: Persistence

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GrammarMistakeEntry].self, from: data) else { return }
        entries = decoded
    }
}

// MARK: - Lesson feedback store

/// Small local log of the learner's lesson ratings. Negative feedback's reasons
/// are fed back into regeneration to fix the specific complaint. Local-only
/// (diagnostic) — not part of cross-device backup.
@Observable
final class GrammarFeedbackStore {
    private(set) var entries: [GrammarLessonFeedback] = []

    private let filename = "grammarFeedback.v1.json"

    init() { load() }

    func add(_ entry: GrammarLessonFeedback) {
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        persist()
    }

    func clear() { entries.removeAll(); persist() }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GrammarLessonFeedback].self, from: data) else { return }
        entries = decoded
    }
}
