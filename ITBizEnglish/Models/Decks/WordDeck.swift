//
//  WordDeck.swift
//  ITBizEnglish
//
//  Memrise-style learning models. A WordDeck (≈ a Memrise course) holds many
//  DeckWords. Each word tracks its own learning progress via `correctCount`
//  (0...10) and a spaced-repetition `nextReviewDate`.
//
//  NOTE: named `DeckWord` (not `VocabularyWord`) to avoid colliding with the
//  app's existing SM-2 `VocabularyWord`. Fields match the requested spec.
//

import Foundation
import SwiftUI

struct DeckWord: Codable, Identifiable, Hashable {
    var id = UUID()
    var word: String            // English
    var meaning: String         // Vietnamese
    var pronunciation: String   // IPA or phonetic hint
    var example: String         // example sentence (English)

    /// Part of speech, short Vietnamese label (e.g. "động từ", "danh từ").
    /// Optional so decks saved before this field still decode (missing → nil).
    var partOfSpeech: String? = nil

    /// Learning progress, 0...`masteryGoal`. Reaches goal => mastered.
    var correctCount: Int = 0

    /// When this word is next due for review. `nil` while still being learned.
    var nextReviewDate: Date? = nil

    /// Current review interval in days (drives the 1→3→7→14… progression).
    /// Not part of the original spec but required to grow review spacing.
    var intervalDays: Int = 0

    /// User-flagged "hard" word — grouped for extra review.
    var isDifficult: Bool = false

    static let masteryGoal = 6

    // MARK: - Derived

    var isNew: Bool { correctCount == 0 }
    var isMastered: Bool { correctCount >= Self.masteryGoal }
    var isLearning: Bool { correctCount > 0 && correctCount < Self.masteryGoal }

    /// 0...1 progress toward mastery.
    var progress: Double {
        min(1, Double(correctCount) / Double(Self.masteryGoal))
    }

    /// Due for review now? Learning words (no review date) are always available.
    func isDue(asOf date: Date = .now) -> Bool {
        guard let nextReviewDate else { return true }
        return nextReviewDate <= date
    }
}

struct WordDeck: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var words: [DeckWord]
    var createdAt: Date = .now
    /// SF Symbol shown as the deck's avatar.
    var icon: String = "leaf.fill"
    /// Accent color (hex) for the deck's avatar tile & progress.
    var colorHex: UInt32 = 0x58CC02

    enum CodingKeys: String, CodingKey { case id, title, words, createdAt, icon, colorHex }

    // MARK: - Derived stats

    var masteredCount: Int { words.filter(\.isMastered).count }
    var total: Int { words.count }

    var progress: Double {
        total == 0 ? 0 : Double(masteredCount) / Double(total)
    }

    /// Words available to study right now (new, learning, or due review).
    var studyableWords: [DeckWord] {
        words.filter { !$0.isMastered || $0.isDue() }
    }

    /// Words seen at least once (used by Speed Review — no brand-new words).
    var learnedWords: [DeckWord] {
        words.filter { !$0.isNew }
    }

    var dueReviewCount: Int {
        words.filter { $0.isMastered && $0.isDue() }.count
    }

    /// Words due for spaced-repetition review (mastered and their date has come).
    var reviewableWords: [DeckWord] {
        words.filter { $0.isMastered && $0.isDue() }
    }

    /// Words the user flagged as hard — practised from their own section.
    var difficultWords: [DeckWord] {
        words.filter(\.isDifficult)
    }

    var difficultCount: Int { difficultWords.count }

    var accent: Color { Color(hex: colorHex) }
}

// Custom decoding (in an extension to keep the memberwise initializer) so decks
// saved before `icon` existed still load, defaulting to the leaf symbol.
extension WordDeck {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        words = try c.decode([DeckWord].self, forKey: .words)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "leaf.fill"
        colorHex = try c.decodeIfPresent(UInt32.self, forKey: .colorHex) ?? 0x58CC02
    }
}

/// Curated SF Symbols offered as deck avatars.
enum DeckIcon {
    static let choices = [
        "leaf.fill", "book.fill", "graduationcap.fill", "briefcase.fill",
        "laptopcomputer", "chevron.left.forwardslash.chevron.right", "globe", "flag.fill",
        "star.fill", "heart.fill", "bolt.fill", "flame.fill",
        "brain.head.profile", "lightbulb.fill", "cup.and.saucer.fill", "gamecontroller.fill"
    ]
}

// MARK: - Sample

extension WordDeck {
    static let sample = WordDeck(
        title: "IT Standup Essentials",
        words: [
            DeckWord(word: "blocker", meaning: "việc cản trở khiến không tiếp tục được",
                     pronunciation: "/ˈblɒkə/", example: "I have a blocker on the API integration."),
            DeckWord(word: "to deploy", meaning: "triển khai code lên môi trường chạy thật",
                     pronunciation: "/dɪˈplɔɪ/", example: "We'll deploy the build this afternoon."),
            DeckWord(word: "pull request", meaning: "yêu cầu merge code để review",
                     pronunciation: "/pʊl rɪˈkwest/", example: "Can you review my pull request?"),
            DeckWord(word: "edge case", meaning: "trường hợp hiếm/biên cần xử lý riêng",
                     pronunciation: "/edʒ keɪs/", example: "Let's add a test for this edge case."),
            DeckWord(word: "to refactor", meaning: "viết lại code cho gọn mà không đổi hành vi",
                     pronunciation: "/ˌriːˈfæktə/", example: "I'll refactor this view model later."),
            DeckWord(word: "scope creep", meaning: "phạm vi công việc phình ra ngoài kế hoạch",
                     pronunciation: "/skəʊp kriːp/", example: "Watch out for scope creep this sprint.")
        ]
    )
}
