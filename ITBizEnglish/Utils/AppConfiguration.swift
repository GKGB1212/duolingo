//
//  AppConfiguration.swift
//  ITBizEnglish
//
//  Configuration + the app's LLM access layer:
//   • AppConfiguration — exposes whether the user has added any API key. The app
//     ships NO built-in key: every user brings their own (free) key.
//   • LLMProvider / APICredential — a provider + key the user adds (onboarding
//     gate or Settings), with sign-up URL + step-by-step guide per provider.
//   • AppSettings — persisted user settings: API credentials (rotated across
//     providers to spread free-tier rate limits) and the preferred appearance.
//   • LLMClient — one entry point all services call; picks the next credential,
//     formats the request for its provider, and fails over to the next key on
//     rate-limit / bad-key / transient errors.
//

import Foundation
import SwiftUI
import Observation

enum AppConfiguration {

    /// True when the user has added at least one API credential. The app no
    /// longer ships a built-in key — every user brings their own (free) key,
    /// added on the onboarding gate or in Settings.
    static var hasGeminiKey: Bool { AppSettings.shared.hasCredential }
}

// MARK: - Providers

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case gemini, groq, openRouter, cerebras, mistral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini:     return "Google Gemini"
        case .groq:       return "Groq"
        case .openRouter: return "OpenRouter"
        case .cerebras:   return "Cerebras"
        case .mistral:    return "Mistral"
        }
    }

    var isGemini: Bool { self == .gemini }

    /// Default model id per provider (free-tier friendly).
    var defaultModel: String {
        switch self {
        case .gemini:     return "gemini-2.5-flash"
        case .groq:       return "llama-3.3-70b-versatile"
        case .openRouter: return "meta-llama/llama-3.3-70b-instruct:free"
        case .cerebras:   return "llama-3.3-70b"
        case .mistral:    return "mistral-large-latest"
        }
    }

    /// Base URL for OpenAI-compatible `/chat/completions` (nil for Gemini).
    var openAIBaseURL: String? {
        switch self {
        case .gemini:     return nil
        case .groq:       return "https://api.groq.com/openai/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .cerebras:   return "https://api.cerebras.ai/v1"
        case .mistral:    return "https://api.mistral.ai/v1"
        }
    }

    /// Where to grab a free key — shown as a hint in Settings.
    var keyHint: String {
        switch self {
        case .gemini:     return "aistudio.google.com/apikey"
        case .groq:       return "console.groq.com/keys"
        case .openRouter: return "openrouter.ai/keys"
        case .cerebras:   return "cloud.cerebras.ai"
        case .mistral:    return "console.mistral.ai/api-keys"
        }
    }

    /// Full URL of the provider's API-key page (opened from the in-app guide).
    var signupURL: URL { URL(string: "https://\(keyHint)")! }

    /// Suggested first choice for new users — easiest, most generous free tier.
    var isRecommended: Bool { self == .gemini }

    /// One-line pitch shown under the provider name in the guide.
    var blurb: String {
        switch self {
        case .gemini:     return "Dễ lấy nhất, hạn mức miễn phí rộng rãi — khuyên dùng cho người mới."
        case .groq:       return "Tốc độ rất nhanh, có gói miễn phí."
        case .openRouter: return "Gộp nhiều model, có nhiều model gắn nhãn :free."
        case .cerebras:   return "Suy luận cực nhanh, có gói miễn phí."
        case .mistral:    return "Model của Mistral (Pháp), có gói dùng thử miễn phí."
        }
    }

    /// Step-by-step (Vietnamese) instructions for getting a free key.
    var keySteps: [String] {
        switch self {
        case .gemini:
            return [
                "Mở Google AI Studio và đăng nhập bằng tài khoản Google.",
                "Bấm “Create API key” (Tạo khóa API).",
                "Chọn hoặc tạo một project (miễn phí, không cần thẻ ngân hàng).",
                "Sao chép khóa bắt đầu bằng “AIza…” rồi quay lại dán vào ô thêm key."
            ]
        case .groq:
            return [
                "Đăng ký / đăng nhập Groq Console (qua Google hoặc email).",
                "Vào mục “API Keys” ở menu bên trái.",
                "Bấm “Create API Key” và đặt tên bất kỳ.",
                "Sao chép khóa “gsk_…” (chỉ hiện 1 lần) rồi dán vào ô thêm key."
            ]
        case .openRouter:
            return [
                "Đăng nhập OpenRouter bằng Google, GitHub hoặc email.",
                "Mở trang “Keys”.",
                "Bấm “Create Key” và đặt tên.",
                "Sao chép khóa “sk-or-…” rồi dán vào ô thêm key."
            ]
        case .cerebras:
            return [
                "Đăng ký Cerebras Cloud (miễn phí).",
                "Vào mục “API Keys”.",
                "Bấm “Generate API Key”.",
                "Sao chép khóa rồi dán vào ô thêm key."
            ]
        case .mistral:
            return [
                "Đăng nhập Mistral AI Console.",
                "Mở mục “API Keys”.",
                "Bấm “Create new key”.",
                "Sao chép khóa rồi dán vào ô thêm key."
            ]
        }
    }

    /// Accent color for the provider's badge / open-key button (reuses the
    /// app palette so the 3D buttons get a matching darker edge below).
    var tint: Color {
        switch self {
        case .gemini:     return .duoBlue
        case .groq:       return .duoGold
        case .openRouter: return .duoIndigo
        case .cerebras:   return .duoGreen
        case .mistral:    return .duoRed
        }
    }
    var tintEdge: Color {
        switch self {
        case .gemini:     return .duoBlueEdge
        case .groq:       return .duoGoldEdge
        case .openRouter: return .duoIndigoEdge
        case .cerebras:   return .duoGreenEdge
        case .mistral:    return .duoRedEdge
        }
    }
}

/// One configured (provider, key) the app can use.
struct APICredential: Codable, Identifiable, Hashable {
    var id = UUID()
    var provider: LLMProvider
    var key: String
    /// Optional model override; falls back to the provider default.
    var model: String? = nil

    var resolvedModel: String {
        let m = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? provider.defaultModel : m
    }
}

// MARK: - User settings

@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// App-wide accent theme — recolors primary buttons, tint, progress, etc.
    enum AppTheme: String, CaseIterable, Identifiable {
        case feather, sky, plum, pink, navy, brown

        var id: String { rawValue }
        var label: String {
            switch self {
            case .feather: return "Xanh lá"
            case .sky:     return "Xanh dương"
            case .plum:    return "Tím"
            case .pink:    return "Hồng phấn"
            case .navy:    return "Navy"
            case .brown:   return "Nâu"
            }
        }
        var primaryHex: UInt32 {
            switch self {
            case .feather: return 0x58CC02
            case .sky:     return 0x1CB0F6
            case .plum:    return 0xA560E8
            case .pink:    return 0xFF6FB5
            case .navy:    return 0x3D5A98
            case .brown:   return 0xB07D56
            }
        }
        var edgeHex: UInt32 {
            switch self {
            case .feather: return 0x4CAF00
            case .sky:     return 0x1899D6
            case .plum:    return 0x8A4FC4
            case .pink:    return 0xE25C9E
            case .navy:    return 0x2E4778
            case .brown:   return 0x8E6242
            }
        }
        var primary: Color { Color(hex: primaryHex) }
        var edge: Color { Color(hex: edgeHex) }

        /// Very light pastel tint of the theme used as the screen background
        /// (adapts to dark mode).
        var background: Color {
            switch self {
            case .feather: return Color(.systemBackground)   // green keeps plain white/black
            case .sky:     return Color.dyn(0xEAF7FE, 0x0A1014)
            case .plum:    return Color.dyn(0xF6EFFC, 0x120E16)
            case .pink:    return Color.dyn(0xFFEFF7, 0x16090F)
            case .navy:    return Color.dyn(0xEEF1F8, 0x0B0E16)
            case .brown:   return Color.dyn(0xF7F1EA, 0x140F0A)
            }
        }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Hệ thống"
            case .light:  return "Sáng"
            case .dark:   return "Tối"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }

    /// User-added API credentials (provider + key).
    var credentials: [APICredential] {
        didSet { persistCredentials(); rotationIndex = 0 }
    }

    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    /// Identifier of the chosen text-to-speech voice (`AVSpeechSynthesisVoice`).
    /// `nil` means "let the app pick the best installed English voice".
    var voiceIdentifier: String? {
        didSet {
            if let id = voiceIdentifier {
                UserDefaults.standard.set(id, forKey: Self.voiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.voiceKey)
            }
        }
    }

    /// Whether the floating quick-lookup bubble is shown app-wide.
    var lookupBubbleEnabled: Bool {
        didSet { UserDefaults.standard.set(lookupBubbleEnabled, forKey: Self.lookupBubbleKey) }
    }

    /// Whether a freshly generated grammar lesson runs an extra low-temperature
    /// AI pass that double-checks the exercise answer keys before showing them.
    /// Costs one more API call per generation; users on tight quotas can turn it
    /// off (structural validation still runs either way).
    var verifyGrammar: Bool {
        didSet { UserDefaults.standard.set(verifyGrammar, forKey: Self.grammarVerifyKey) }
    }

    /// Summary of the credential used for the most recent successful AI call,
    /// e.g. "Groq · llama-3.3-70b · …a1b2" — transient, for display only.
    var lastUsedSummary: String?

    @ObservationIgnored private var rotationIndex = 0
    @ObservationIgnored private static let credsKey = "itbiz.apiCreds.v1"
    @ObservationIgnored private static let legacyKeysKey = "itbiz.geminiKeys.v1"
    @ObservationIgnored private static let appearanceKey = "itbiz.appearance.v1"
    @ObservationIgnored private static let themeKey = "itbiz.theme.v1"
    @ObservationIgnored private static let voiceKey = "itbiz.voiceID.v1"
    @ObservationIgnored private static let lookupBubbleKey = "itbiz.lookupBubble.v1"
    @ObservationIgnored private static let grammarVerifyKey = "itbiz.grammarVerify.v1"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? Appearance.system.rawValue
        appearance = Appearance(rawValue: raw) ?? .system
        let themeRaw = UserDefaults.standard.string(forKey: Self.themeKey) ?? AppTheme.feather.rawValue
        theme = AppTheme(rawValue: themeRaw) ?? .feather
        voiceIdentifier = UserDefaults.standard.string(forKey: Self.voiceKey)
        // Default ON when the user hasn't set it yet.
        lookupBubbleEnabled = UserDefaults.standard.object(forKey: Self.lookupBubbleKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.lookupBubbleKey)
        // Default ON — answer-key verification protects learner trust.
        verifyGrammar = UserDefaults.standard.object(forKey: Self.grammarVerifyKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.grammarVerifyKey)

        // Load credentials, migrating the old [String] of Gemini keys if present.
        if let data = UserDefaults.standard.data(forKey: Self.credsKey),
           let decoded = try? JSONDecoder().decode([APICredential].self, from: data) {
            credentials = decoded
        } else if let legacy = UserDefaults.standard.stringArray(forKey: Self.legacyKeysKey) {
            credentials = legacy
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { APICredential(provider: .gemini, key: $0) }
            UserDefaults.standard.removeObject(forKey: Self.legacyKeysKey)
        } else {
            credentials = []
        }
    }

    private func persistCredentials() {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: Self.credsKey)
        }
    }

    /// All usable credentials the user has added (the app ships no built-in key).
    var allCredentials: [APICredential] {
        credentials.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var hasCredential: Bool { !allCredentials.isEmpty }

    /// A full rotation order starting at a moving offset, so successive calls
    /// begin with a different credential (round-robin) while still letting the
    /// caller fail over through the rest of the list.
    func rotationOrder() -> [APICredential] {
        let all = allCredentials
        guard !all.isEmpty else { return [] }
        let start = rotationIndex % all.count
        rotationIndex += 1
        return Array(all[start...]) + Array(all[..<start])
    }

    // MARK: - Editing

    func addCredential(provider: LLMProvider, key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty,
              !credentials.contains(where: { $0.provider == provider && $0.key == k }) else { return }
        credentials.append(APICredential(provider: provider, key: k))
    }

    func removeCredentials(at offsets: IndexSet) {
        credentials.remove(atOffsets: offsets)
    }

    /// Replaces all user-added API credentials (used when importing a backup).
    /// `didSet` persists. Pass an empty array to leave keys untouched on restore.
    func restore(credentials: [APICredential]) {
        guard !credentials.isEmpty else { return }
        self.credentials = credentials
    }
}

// MARK: - Unified LLM client

/// One place that turns a (system prompt, user text) pair into the model's text
/// output, regardless of provider. All services call this so provider rotation
/// and failover live in a single spot.
enum LLMClient {

    /// Sends the prompt and returns the model's raw text content (expected to be
    /// JSON for our use). Rotates across configured credentials and fails over
    /// to the next one on rate-limit / bad-key / transient errors.
    static func generateJSON(system: String, user: String, temperature: Double) async throws -> String {
        let order = AppSettings.shared.rotationOrder()
        guard !order.isEmpty else { throw TranslationError.missingKey }

        var lastError: Error = TranslationError.network
        for cred in order {
            do {
                let request = try makeRequest(cred: cred, system: system, user: user, temperature: temperature)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw TranslationError.network }

                if (200..<300).contains(http.statusCode) {
                    let content = try extractContent(provider: cred.provider, data: data)
                    let summary = describe(cred)
                    await MainActor.run { AppSettings.shared.lastUsedSummary = summary }
                    return content
                }
                // Retryable on another key: rate limit, auth/quota, server hiccup.
                lastError = mapHTTP(status: http.statusCode)
                if [429, 401, 403, 400, 500, 503].contains(http.statusCode) { continue }
                throw lastError
            } catch let error as TranslationError {
                lastError = error
                continue   // try the next credential
            } catch let urlError as URLError {
                lastError = TranslationError.server(networkReason(urlError))
                continue
            } catch {
                lastError = TranslationError.network
                continue
            }
        }
        throw lastError
    }

    /// Turns a low-level `URLError` into a clear Vietnamese reason so the user
    /// knows whether it's their connection, a timeout, or a blocked host.
    private static func networkReason(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "Không có kết nối Internet. Kiểm tra mạng (Wi-Fi/4G) rồi thử lại."
        case .timedOut:
            return "Hết thời gian chờ máy chủ AI — mạng yếu hoặc đang bị chặn. Thử lại nhé."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Không kết nối được tới máy chủ AI (có thể do mạng / VPN / tường lửa chặn)."
        case .networkConnectionLost:
            return "Mất kết nối giữa chừng. Thử lại nhé."
        default:
            return "Không gọi được dịch vụ AI (mã \(error.code.rawValue)). Kiểm tra mạng và thử lại."
        }
    }

    // MARK: - Request building

    private static func makeRequest(cred: APICredential, system: String,
                                    user: String, temperature: Double) throws -> URLRequest {
        if cred.provider.isGemini {
            return try makeGeminiRequest(cred: cred, system: system, user: user, temperature: temperature)
        } else {
            return try makeOpenAIRequest(cred: cred, system: system, user: user, temperature: temperature)
        }
    }

    private static func makeGeminiRequest(cred: APICredential, system: String,
                                          user: String, temperature: Double) throws -> URLRequest {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(cred.resolvedModel):generateContent?key=\(cred.key)"
        guard let url = URL(string: endpoint) else { throw TranslationError.network }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["parts": [["text": user]]]],
            "generationConfig": [
                "temperature": temperature,
                "responseMimeType": "application/json"
            ],
            // Don't let the safety filter refuse legitimate content (e.g. mature
            // song lyrics the user explicitly asked to translate faithfully).
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func makeOpenAIRequest(cred: APICredential, system: String,
                                          user: String, temperature: Double) throws -> URLRequest {
        guard let base = cred.provider.openAIBaseURL,
              let url = URL(string: base + "/chat/completions") else { throw TranslationError.network }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cred.key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": cred.resolvedModel,
            "temperature": temperature,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Short label of the credential used, with only the last 4 chars of the key.
    private static func describe(_ cred: APICredential) -> String {
        let tail = cred.key.count > 4 ? String(cred.key.suffix(4)) : cred.key
        return "\(cred.provider.label) · \(cred.resolvedModel) · …\(tail)"
    }

    // MARK: - Response parsing

    private static func extractContent(provider: LLMProvider, data: Data) throws -> String {
        let text: String?
        if provider.isGemini {
            text = (try? JSONDecoder().decode(GeminiEnvelope.self, from: data))?
                .candidates?.first?.content?.parts?.first?.text
        } else {
            text = (try? JSONDecoder().decode(OpenAIEnvelope.self, from: data))?
                .choices?.first?.message?.content
        }
        guard let content = text, !content.isEmpty else { throw TranslationError.decoding }
        return stripFences(content)
    }

    private static func stripFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private static func mapHTTP(status: Int) -> TranslationError {
        switch status {
        case 401, 403: return .server("API key bị từ chối hoặc hết hạn mức.")
        case 429:      return .server("Đã chạm giới hạn (free tier). Thử thêm key khác trong Cài đặt.")
        case 500, 503: return .server("Nhà cung cấp tạm thời quá tải. Thử lại sau.")
        default:       return .server("Yêu cầu thất bại (HTTP \(status)).")
        }
    }

    // Minimal response shapes.
    private struct GeminiEnvelope: Decodable {
        let candidates: [Candidate]?
        struct Candidate: Decodable { let content: Content? }
        struct Content: Decodable { let parts: [Part]? }
        struct Part: Decodable { let text: String? }
    }
    private struct OpenAIEnvelope: Decodable {
        let choices: [Choice]?
        struct Choice: Decodable { let message: Message? }
        struct Message: Decodable { let content: String? }
    }
}
