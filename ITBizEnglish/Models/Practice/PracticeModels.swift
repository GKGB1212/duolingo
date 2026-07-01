//
//  PracticeModels.swift
//  ITBizEnglish
//
//  Self-Translate practice: the user collects Vietnamese sentences they expect
//  to use, writes the English themselves, and Gemini evaluates the attempt
//  (the reference answer is only a hint — not a strict key). AI feedback is
//  cached on the sentence so it can be reused without re-calling the API.
//

import Foundation
import SwiftUI

/// Cached AI evaluation of a user's English attempt.
struct AIFeedback: Codable, Hashable {
    var score: Int               // 0...100 — how well the attempt conveys the meaning
    var verdict: String          // short label, e.g. "Natural", "Needs work"
    var correctedVersion: String // an improved/correct English version
    var notes: [String]          // specific things to fix (empty if perfect)
    var checkedAt: Date = .now

    var ratingColor: Color {
        switch score {
        case 85...:  return .green
        case 60..<85: return .orange
        default:     return .red
        }
    }
    var emoji: String {
        switch score {
        case 85...:  return "🎉"
        case 60..<85: return "👍"
        default:     return "💪"
        }
    }
}

/// One archived attempt at a sentence: what the user wrote and how the AI
/// graded it, tagged with the practice session it belonged to. Kept so the user
/// can look back and compare how their translations improve over time.
struct PracticeAttempt: Codable, Identifiable, Hashable {
    var id = UUID()
    var session: Int             // which session number this belonged to
    var attempt: String          // the user's English at the time
    var feedback: AIFeedback?    // AI result (or synthetic from word-bank)
    var date: Date = .now
}

struct PracticeSentence: Codable, Identifiable, Hashable {
    var id = UUID()
    var vietnamese: String
    /// Optional reference English (a hint, AI-suggested or user-entered).
    var referenceEnglish: String = ""
    /// The user's most recent attempt.
    var lastAttempt: String = ""
    /// Cached AI feedback for the last checked attempt.
    var feedback: AIFeedback? = nil
    var createdAt: Date = .now
    /// Past attempts from completed sessions (newest sessions appended last).
    var history: [PracticeAttempt] = []
    /// User-flagged as hard, so it can be reviewed on its own. Persists across
    /// sessions (a new session clears attempts/feedback but keeps this flag).
    var isDifficult: Bool = false

    var hasBeenChecked: Bool { feedback != nil }
}

extension PracticeSentence {
    enum CodingKeys: String, CodingKey {
        case id, vietnamese, referenceEnglish, lastAttempt, feedback, createdAt, history, isDifficult
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        vietnamese = try c.decode(String.self, forKey: .vietnamese)
        referenceEnglish = try c.decodeIfPresent(String.self, forKey: .referenceEnglish) ?? ""
        lastAttempt = try c.decodeIfPresent(String.self, forKey: .lastAttempt) ?? ""
        feedback = try c.decodeIfPresent(AIFeedback.self, forKey: .feedback)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        history = try c.decodeIfPresent([PracticeAttempt].self, forKey: .history) ?? []
        isDifficult = try c.decodeIfPresent(Bool.self, forKey: .isDifficult) ?? false
    }
}

struct PracticeSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var sentences: [PracticeSentence]
    var createdAt: Date = .now
    /// SF Symbol avatar + accent color (hex).
    var icon: String = "pencil.and.scribble"
    var colorHex: UInt32 = 0xA560E8
    /// Current practice session number (1-based). Bumped each "new session".
    var session: Int = 1

    enum CodingKeys: String, CodingKey { case id, title, sentences, createdAt, icon, colorHex, session }

    var checkedCount: Int { sentences.filter(\.hasBeenChecked).count }
    var total: Int { sentences.count }

    /// Sentences the user flagged as hard, in list order.
    var difficultSentences: [PracticeSentence] { sentences.filter(\.isDifficult) }
    var difficultCount: Int { difficultSentences.count }
    var progress: Double { total == 0 ? 0 : Double(checkedCount) / Double(total) }

    var accent: Color { Color(hex: colorHex) }

    /// Every sentence has been checked at least once this session.
    var isComplete: Bool { total > 0 && checkedCount == total }

    /// Average AI score of the checked sentences this session (0 if none).
    var currentAverage: Int {
        let scores = sentences.compactMap { $0.feedback?.score }
        guard !scores.isEmpty else { return 0 }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    /// True once any sentence has an archived past attempt.
    var hasHistory: Bool { sentences.contains { !$0.history.isEmpty } }
}

extension PracticeSet {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sentences = try c.decode([PracticeSentence].self, forKey: .sentences)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "pencil.and.scribble"
        colorHex = try c.decodeIfPresent(UInt32.self, forKey: .colorHex) ?? 0xA560E8
        session = try c.decodeIfPresent(Int.self, forKey: .session) ?? 1
    }
}

// MARK: - Sample

extension PracticeSet {
    static let sample = PracticeSet(
        title: "Daily Standup",
        sentences: [
            PracticeSentence(vietnamese: "Hôm qua mình đã hoàn thành màn hình đăng nhập.",
                             referenceEnglish: "Yesterday I finished the login screen."),
            PracticeSentence(vietnamese: "Hôm nay mình sẽ xử lý phần tích hợp API.",
                             referenceEnglish: "Today I'll work on the API integration."),
            PracticeSentence(vietnamese: "Mình đang bị vướng ở chỗ phân quyền người dùng.",
                             referenceEnglish: "I'm blocked on the user permissions.")
        ]
    )
}
