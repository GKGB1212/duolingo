//
//  ChatAIService.swift
//  ITBizEnglish
//
//  "Chat with AI" — role-play workplace conversations to practice spoken English.
//  The user picks a work scenario (standup, code review, interview…), chats turn
//  by turn, and the AI both replies in character AND estimates how far the user
//  has progressed toward the scenario's goal. When the user ends, a separate
//  call grades the whole conversation.
//
//  All network calls go through the shared `LLMClient` (provider rotation).
//

import SwiftUI
import Observation

// MARK: - Models

/// A work conversation scenario the user can practice.
struct ChatTopic: Identifiable, Hashable {
    let id: String
    let title: String        // Vietnamese label
    let subtitle: String     // short Vietnamese description
    let icon: String         // SF Symbol
    let colorHex: UInt32
    let goal: String         // English scenario goal (fed to the AI + progress)

    var color: Color { Color(hex: colorHex) }

    static let all: [ChatTopic] = [
        .init(id: "standup", title: "Daily Standup", subtitle: "Báo cáo tiến độ với team mỗi sáng",
              icon: "sun.max.fill", colorHex: 0xFF9600,
              goal: "Give your daily standup update: what you did yesterday, what you'll do today, and any blockers."),
        .init(id: "sprint", title: "Sprint Planning", subtitle: "Ước lượng & nhận task cho sprint",
              icon: "list.bullet.clipboard.fill", colorHex: 0x1CB0F6,
              goal: "Discuss and estimate tasks, decide what to commit to this sprint, and raise any concerns."),
        .init(id: "codeReview", title: "Code Review", subtitle: "Trao đổi nhận xét pull request",
              icon: "chevron.left.forwardslash.chevron.right", colorHex: 0xA560E8,
              goal: "Discuss feedback on a pull request: explain your code and respond to the reviewer's comments."),
        .init(id: "oneOnOne", title: "1:1 với Sếp", subtitle: "Phản hồi & định hướng phát triển",
              icon: "person.2.fill", colorHex: 0x3D5A98,
              goal: "Have a 1:1 with your manager: share how things are going, give feedback, and talk about growth."),
        .init(id: "interview", title: "Phỏng vấn", subtitle: "Phỏng vấn vị trí Frontend Developer",
              icon: "briefcase.fill", colorHex: 0x58CC02,
              goal: "Answer common frontend developer interview questions about your experience and skills."),
        .init(id: "bug", title: "Báo lỗi khẩn", subtitle: "Mô tả & xử lý một production bug",
              icon: "ladybug.fill", colorHex: 0xFF4B4B,
              goal: "Report a production bug to your team: describe it, its impact, and propose next steps."),
        .init(id: "dayoff", title: "Xin nghỉ phép", subtitle: "Đề nghị nghỉ với quản lý",
              icon: "calendar", colorHex: 0xFFC800,
              goal: "Politely ask your manager for time off and arrange how your work will be covered."),
        .init(id: "smalltalk", title: "Tán gẫu", subtitle: "Small talk với đồng nghiệp",
              icon: "cup.and.saucer.fill", colorHex: 0xB07D56,
              goal: "Make friendly small talk with a coworker about the weekend, hobbies, and work life."),
        .init(id: "demo", title: "Demo sản phẩm", subtitle: "Trình bày tính năng cho khách hàng",
              icon: "play.rectangle.fill", colorHex: 0xFF6FB5,
              goal: "Demo a new feature to a client: explain what it does and answer their questions."),
        .init(id: "deadline", title: "Thương lượng deadline", subtitle: "Đàm phán thời hạn hợp lý",
              icon: "clock.badge.exclamationmark.fill", colorHex: 0x8A4FC4,
              goal: "Negotiate a realistic deadline with your manager or client, explaining the trade-offs.")
    ]
}

/// Difficulty of the role-play — tunes how the AI partner speaks.
enum ChatLevel: String, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }

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

    /// Instruction injected into the AI system prompt.
    var guidance: String {
        switch self {
        case .easy:
            return "LEVEL = EASY. Use very simple, common vocabulary and short sentences (max ~12 words). Be patient, slow and encouraging; avoid idioms and slang; ask simple questions."
        case .medium:
            return "LEVEL = MEDIUM. Use natural everyday business/IT English at a normal pace; common phrasal verbs and collocations are fine."
        case .hard:
            return "LEVEL = HARD. Speak like a fluent native professional: richer vocabulary, idioms, and faster, more demanding follow-up questions. Challenge the user and don't over-simplify."
        }
    }
}

/// One line of the conversation.
struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case ai, user }
    let id = UUID()
    let role: Role
    var text: String
    /// Vietnamese translation of an AI line (revealed on demand).
    var translation: String? = nil
    var date = Date()
}

/// AI evaluation of the whole conversation (the user's English only).
struct ChatReview: Hashable, Codable {
    var score: Int
    var verdict: String
    var strengths: [String]
    var improvements: [String]

    var ratingColor: Color { score >= 85 ? .duoGreen : (score >= 60 ? .duoGold : .duoRed) }
    var emoji: String { score >= 85 ? "🎉" : (score >= 60 ? "👍" : "💪") }
    var didWell: Bool { score >= 60 }
}

// MARK: - Service

struct ChatAIService {

    /// One reply from the AI partner: English text, a Vietnamese translation
    /// (revealed on demand), a progress estimate, and up to 3 suggested English
    /// replies the user could send next.
    struct Turn { let reply: String; let vi: String; let progress: Int; let suggestions: [String] }

    // MARK: Reply

    func nextReply(topic: ChatTopic, level: ChatLevel, history: [ChatMessage]) async throws -> Turn {
        let content = try await LLMClient.generateJSON(
            system: replySystemPrompt(topic, level),
            user: replyUserPrompt(history),
            temperature: 0.8)
        guard let data = content.data(using: .utf8),
              let dto = try? JSONDecoder().decode(TurnDTO.self, from: data),
              let reply = dto.reply?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else {
            throw TranslationError.decoding
        }
        let suggestions = (dto.suggestions ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
        return Turn(reply: reply,
                    vi: dto.vi?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    progress: min(100, max(0, dto.progress ?? 0)),
                    suggestions: Array(suggestions))
    }

    private func replySystemPrompt(_ topic: ChatTopic, _ level: ChatLevel) -> String {
        """
        You are role-playing a realistic workplace conversation in English to help a Vietnamese software developer practice speaking.

        Scenario: \(topic.title) — \(topic.goal)
        \(level.guidance)

        Rules:
        - Play the OTHER person in this scenario (teammate, manager, interviewer, client…). Stay fully in character.
        - Speak natural, concise spoken English (1–3 short sentences). Use common IT / business vocabulary.
        - Drive the conversation toward the scenario goal and ask a follow-up question so the user keeps talking.
        - If the user makes a small English mistake, you may naturally model the correct phrasing in your reply, but never lecture.
        - Be warm and encouraging.
        - "vi" = a natural Vietnamese translation of your reply.
        - "progress" = your estimate (0–100) of how fully the USER has accomplished the scenario goal so far. Start low; only reach 100 when the goal is clearly achieved.
        - "suggestions" = exactly 3 short, natural English replies the USER could send next to answer YOU and move toward the goal. Write them from the USER's point of view (first person), varied, and fitting the level (\(level.rawValue)). Keep each under ~12 words.

        Respond ONLY with raw JSON, no markdown:
        {"reply": "your spoken reply in English", "vi": "bản dịch tiếng Việt", "progress": <int 0-100>, "suggestions": ["...", "...", "..."]}
        """
    }

    private func replyUserPrompt(_ history: [ChatMessage]) -> String {
        guard !history.isEmpty else {
            return "The conversation hasn't started. Greet the user warmly and open the scenario in 1–2 sentences, then ask a question. Set progress to a small number."
        }
        let convo = history.map { ($0.role == .user ? "User: " : "You: ") + $0.text }
            .joined(separator: "\n")
        return "Conversation so far:\n\(convo)\n\nReply as your character (the 'You' role) and update progress."
    }

    private struct TurnDTO: Decodable { let reply: String?; let vi: String?; let progress: Int?; let suggestions: [String]? }

    // MARK: Review

    func review(topic: ChatTopic, level: ChatLevel, history: [ChatMessage]) async throws -> ChatReview {
        let content = try await LLMClient.generateJSON(
            system: reviewSystemPrompt(topic, level),
            user: transcript(history),
            temperature: 0.4)
        guard let data = content.data(using: .utf8),
              let dto = try? JSONDecoder().decode(ReviewDTO.self, from: data) else {
            throw TranslationError.decoding
        }
        return ChatReview(
            score: min(100, max(0, dto.score ?? 0)),
            verdict: dto.verdict?.trimmingCharacters(in: .whitespaces) ?? "Đã hoàn thành",
            strengths: (dto.strengths ?? []).filter { !$0.isEmpty },
            improvements: (dto.improvements ?? []).filter { !$0.isEmpty })
    }

    private func reviewSystemPrompt(_ topic: ChatTopic, _ level: ChatLevel) -> String {
        """
        You are a friendly English coach. The user just finished a role-play conversation practicing: \(topic.title) — \(topic.goal) (difficulty: \(level.rawValue)).
        Evaluate ONLY the USER's English (the lines marked 'User:'). Be encouraging but honest.

        Respond ONLY with raw JSON, no markdown:
        {
          "score": <int 0-100 overall>,
          "verdict": "<short Vietnamese label, e.g. 'Khá tự nhiên'>",
          "strengths": ["<short Vietnamese point>"],
          "improvements": ["<short Vietnamese point, include a quick better phrasing>"]
        }
        strengths and improvements: 1–3 short items each.
        """
    }

    private func transcript(_ history: [ChatMessage]) -> String {
        history.map { ($0.role == .user ? "User: " : "Partner: ") + $0.text }
            .joined(separator: "\n")
    }

    private struct ReviewDTO: Decodable {
        let score: Int?
        let verdict: String?
        let strengths: [String]?
        let improvements: [String]?
    }
}

// MARK: - History persistence

/// One finished conversation, archived so the user can review it later. Stores a
/// snapshot of the topic (so it survives even if the topic list later changes).
struct ChatHistoryEntry: Identifiable, Codable {
    let id: UUID
    let topicID: String
    let topicTitle: String
    let topicIcon: String
    let topicColorHex: UInt32
    let levelRaw: String
    let date: Date
    let messages: [ChatMessage]
    let review: ChatReview

    init(id: UUID = UUID(), topic: ChatTopic, level: ChatLevel,
         date: Date = Date(), messages: [ChatMessage], review: ChatReview) {
        self.id = id
        self.topicID = topic.id
        self.topicTitle = topic.title
        self.topicIcon = topic.icon
        self.topicColorHex = topic.colorHex
        self.levelRaw = level.rawValue
        self.date = date
        self.messages = messages
        self.review = review
    }

    var color: Color { Color(hex: topicColorHex) }
    var level: ChatLevel { ChatLevel(rawValue: levelRaw) ?? .medium }
    var userTurns: Int { messages.filter { $0.role == .user }.count }
}

/// Persists finished chat sessions to a JSON file in Application Support
/// (same approach as `DeckStore` / `PracticeStore`). Newest first.
@Observable
final class ChatHistoryStore {
    private(set) var entries: [ChatHistoryEntry] = []

    private let filename = "chatHistory.v1.json"

    init() { load() }

    func add(_ entry: ChatHistoryEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    /// Replaces all history entries (used when importing a backup) and persists.
    func restore(_ entries: [ChatHistoryEntry]) {
        self.entries = entries
        persist()
    }

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
              let decoded = try? JSONDecoder().decode([ChatHistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
