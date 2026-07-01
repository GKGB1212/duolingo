//
//  TranslationResult.swift
//  ITBizEnglish
//
//  Core data model for the Sentence Translator feature.
//

import Foundation

/// The two registers of English the AI returns for a given Vietnamese sentence.
/// `casual`     -> for Slack / Teams chat
/// `professional` -> for Scrum meetings / Emails
struct EnglishOptions: Codable, Hashable {
    let casual: String
    let professional: String
}

/// A single translation result returned by the AI translation API.
///
/// Conforms to `Codable` for JSON (de)serialization and `Identifiable`
/// so it can drive SwiftUI lists / history without extra plumbing.
struct TranslationResult: Codable, Identifiable, Hashable {
    let id: String
    let vietnameseText: String
    let englishOptions: EnglishOptions
    let tags: [String]

    // MARK: - Convenience

    /// Timestamp is generated locally (the API payload doesn't include one),
    /// so it's excluded from Codable and defaulted at init time.
    var createdAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case id, vietnameseText, englishOptions, tags
    }
}

// MARK: - Tone

/// Describes a tone/register so the UI can render each card consistently
/// (label, icon, accent color, usage hint).
enum Tone: String, CaseIterable, Identifiable {
    case casual
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual:       return "Casual"
        case .professional: return "Professional"
        }
    }

    /// Where this tone is typically used — shown as a subtle subtitle.
    var usageHint: String {
        switch self {
        case .casual:       return "Slack / Teams chat"
        case .professional: return "Scrum meetings / Emails"
        }
    }

    var systemImage: String {
        switch self {
        case .casual:       return "bubble.left.and.bubble.right.fill"
        case .professional: return "briefcase.fill"
        }
    }

    /// Reads the matching string out of an `EnglishOptions` value.
    func text(from options: EnglishOptions) -> String {
        switch self {
        case .casual:       return options.casual
        case .professional: return options.professional
        }
    }
}

// MARK: - Mock / Preview Data

extension TranslationResult {
    static let sample = TranslationResult(
        id: UUID().uuidString,
        vietnameseText: "Mình sẽ hoàn thành task này trước cuối ngày.",
        englishOptions: EnglishOptions(
            casual: "I'll get this task done by end of day 👍",
            professional: "I will complete this task by the end of the day."
        ),
        tags: ["Scrum", "Deadline", "Commitment"]
    )
}
