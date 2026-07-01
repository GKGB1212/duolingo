//
//  TranslationService.swift
//  ITBizEnglish
//
//  Abstraction over the AI translation backend.
//  Ships with a mock implementation so the UI is fully functional today;
//  swap in `LiveTranslationService` when the real endpoint is ready.
//

import Foundation

protocol TranslationServicing {
    /// Translates a Vietnamese sentence into casual + professional English.
    func translate(_ vietnameseText: String) async throws -> TranslationResult
}

enum TranslationError: LocalizedError {
    case emptyInput
    case network
    case decoding
    case missingKey
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput: return "Please enter some Vietnamese text to translate."
        case .network:    return "Couldn't reach the translation service. Check your connection and try again."
        case .decoding:   return "The translation response was malformed. Please try again."
        case .missingKey: return "Chưa có API key. Vào Cài đặt ▸ Thêm key (bấm “Hướng dẫn lấy key miễn phí”) để thêm ít nhất 1 key."
        case .server(let message): return message
        }
    }
}

// MARK: - Mock Service

/// Simulates the AI API with a realistic delay and canned-but-varied results.
/// Replace with `LiveTranslationService` later — `TranslationViewModel` only
/// depends on the `TranslationServicing` protocol, so nothing else changes.
struct MockTranslationService: TranslationServicing {

    /// Artificial latency to exercise the loading state. Tweak for demos.
    var delay: Duration = .milliseconds(1200)

    /// When true, occasionally throws to let you test the error UI.
    var simulateFailures: Bool = false

    func translate(_ vietnameseText: String) async throws -> TranslationResult {
        let trimmed = vietnameseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyInput }

        try await Task.sleep(for: delay)

        if simulateFailures, Bool.random() {
            throw TranslationError.network
        }

        // Decode from a JSON blob so this path mirrors the real network code.
        let json = Self.mockJSON(for: trimmed)
        guard let data = json.data(using: .utf8) else {
            throw TranslationError.decoding
        }

        do {
            return try JSONDecoder().decode(TranslationResult.self, from: data)
        } catch {
            throw TranslationError.decoding
        }
    }

    /// Builds a believable JSON payload. The real API will return this shape.
    private static func mockJSON(for text: String) -> String {
        let id = UUID().uuidString
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")

        // A tiny bit of keyword-based variety so demos feel alive.
        let lower = text.lowercased()
        let tags: [String]
        let casual: String
        let professional: String

        switch true {
        case lower.contains("bug") || lower.contains("lỗi"):
            tags = ["Bug", "Engineering", "Standup"]
            casual = "Heads up — I found a bug, looking into it now 🐛"
            professional = "I'd like to flag a defect I've identified; I'm currently investigating the root cause."
        case lower.contains("họp") || lower.contains("meeting"):
            tags = ["Meeting", "Scheduling", "Calendar"]
            casual = "Can we hop on a quick call?"
            professional = "Would you be available for a brief meeting to discuss this further?"
        case lower.contains("deadline") || lower.contains("hạn"):
            tags = ["Deadline", "Commitment", "Scrum"]
            casual = "I'll wrap this up by EOD 👍"
            professional = "I will ensure this is completed by the end of the day."
        default:
            tags = ["General", "Business English", "Communication"]
            casual = "Sure, I can take care of that!"
            professional = "Certainly, I'd be happy to handle that for you."
        }

        let tagJSON = tags.map { "\"\($0)\"" }.joined(separator: ", ")

        return """
        {
          "id": "\(id)",
          "vietnameseText": "\(escaped)",
          "englishOptions": {
            "casual": "\(casual)",
            "professional": "\(professional)"
          },
          "tags": [\(tagJSON)]
        }
        """
    }
}

// MARK: - Live Service (stub)

/// Skeleton for the real implementation. Fill in `endpoint`, auth, and body.
struct LiveTranslationService: TranslationServicing {
    let endpoint: URL
    var apiKey: String = ""

    func translate(_ vietnameseText: String) async throws -> TranslationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": vietnameseText])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TranslationError.network
            }
            do {
                return try JSONDecoder().decode(TranslationResult.self, from: data)
            } catch {
                throw TranslationError.decoding
            }
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.network
        }
    }
}
