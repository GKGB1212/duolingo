//
//  CloudSync.swift
//  ITBizEnglish
//
//  Optional free cloud sync via Firebase — used over its REST API (no SDK), so
//  there's nothing to add to the Xcode project beyond two config values.
//   • CloudConfig   — reads FIREBASE_PROJECT_ID / FIREBASE_API_KEY from
//                     Configuration.plist (same place as the Gemini key).
//   • CloudAuth     — email/password auth via the Identity Toolkit REST API;
//                     keeps the refresh token so the user stays signed in.
//   • CloudSync     — stores ALL app data as one JSON snapshot (reusing
//                     `BackupData`) in Firestore at users/{uid}; upload pushes
//                     local → cloud, download pulls cloud → local.
//
//  Setup (one-time, by the user) is documented in the cloud card in Settings.
//

import Foundation
import Observation

// MARK: - Config

enum CloudConfig {
    static var projectID: String? { plist("FIREBASE_PROJECT_ID") }
    static var apiKey: String? { plist("FIREBASE_API_KEY") }

    /// True once both values are filled in (not the placeholders).
    static var isConfigured: Bool {
        guard let p = projectID, let k = apiKey else { return false }
        return p != "YOUR_FIREBASE_PROJECT_ID" && k != "YOUR_FIREBASE_API_KEY"
    }

    private static func plist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Configuration", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let v = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !v.isEmpty else { return nil }
        return v
    }
}

// MARK: - Errors

enum CloudError: LocalizedError {
    case notConfigured
    case notSignedIn
    case auth(String)     // raw Firebase error code
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Chưa cấu hình Firebase (thiếu Project ID / API key trong Configuration.plist)."
        case .notSignedIn:   return "Bạn chưa đăng nhập tài khoản đám mây."
        case .auth(let code): return Self.friendly(code)
        case .server(let m): return m
        case .decoding:      return "Máy chủ trả về dữ liệu không đọc được."
        }
    }

    /// Maps Firebase auth error codes to Vietnamese.
    private static func friendly(_ code: String) -> String {
        switch code {
        case let c where c.hasPrefix("EMAIL_EXISTS"):            return "Email này đã được đăng ký."
        case let c where c.hasPrefix("INVALID_EMAIL"):           return "Email không hợp lệ."
        case let c where c.hasPrefix("EMAIL_NOT_FOUND"):         return "Không tìm thấy tài khoản với email này."
        case let c where c.hasPrefix("INVALID_PASSWORD"),
             let c where c.hasPrefix("INVALID_LOGIN_CREDENTIALS"): return "Email hoặc mật khẩu không đúng."
        case let c where c.hasPrefix("WEAK_PASSWORD"):           return "Mật khẩu quá yếu (cần ít nhất 6 ký tự)."
        case let c where c.hasPrefix("USER_DISABLED"):           return "Tài khoản đã bị khoá."
        case let c where c.hasPrefix("TOO_MANY_ATTEMPTS"):       return "Thử quá nhiều lần. Đợi một lát rồi thử lại."
        case let c where c.hasPrefix("OPERATION_NOT_ALLOWED"):   return "Chưa bật đăng nhập Email/Password trong Firebase Console."
        default:                                                 return "Lỗi xác thực: \(code)"
        }
    }
}

// MARK: - Auth (Identity Toolkit REST)

@MainActor
@Observable
final class CloudAuth {
    static let shared = CloudAuth()

    private(set) var email: String?
    private(set) var uid: String?
    var isSignedIn: Bool { uid != nil && refreshToken != nil }

    /// Set true after an interactive sign-in/up (not a silent token refresh), so
    /// the app pulls the cloud copy down once after the user logs in.
    @ObservationIgnored var pendingInitialSync = false

    @ObservationIgnored private var idToken: String?
    @ObservationIgnored private var idTokenExpiry: Date = .distantPast
    @ObservationIgnored private var refreshToken: String?

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let kRefresh = "itbiz.cloud.refreshToken"
    private static let kUID = "itbiz.cloud.uid"
    private static let kEmail = "itbiz.cloud.email"

    private init() {
        refreshToken = defaults.string(forKey: Self.kRefresh)
        uid = defaults.string(forKey: Self.kUID)
        email = defaults.string(forKey: Self.kEmail)
    }

    // MARK: Sign up / in / out

    func signUp(email: String, password: String) async throws {
        try await authenticate(endpoint: "signUp", email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        try await authenticate(endpoint: "signInWithPassword", email: email, password: password)
    }

    func signOut() {
        idToken = nil
        idTokenExpiry = .distantPast
        refreshToken = nil
        uid = nil
        email = nil
        defaults.removeObject(forKey: Self.kRefresh)
        defaults.removeObject(forKey: Self.kUID)
        defaults.removeObject(forKey: Self.kEmail)
    }

    /// A currently-valid ID token, refreshed via the refresh token if expired.
    func validIDToken() async throws -> String {
        if let token = idToken, idTokenExpiry > Date().addingTimeInterval(60) { return token }
        guard let refresh = refreshToken else { throw CloudError.notSignedIn }
        try await refreshIDToken(using: refresh)
        guard let token = idToken else { throw CloudError.notSignedIn }
        return token
    }

    // MARK: Internals

    private func authenticate(endpoint: String, email: String, password: String) async throws {
        guard let key = CloudConfig.apiKey else { throw CloudError.notConfigured }
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(endpoint)?key=\(key)")!
        let body = ["email": email, "password": password, "returnSecureToken": "true"]
        let (data, http) = try await CloudHTTP.postJSON(url, body: body)
        guard http.statusCode == 200 else { throw CloudError.auth(Self.errorCode(from: data)) }
        guard let res = try? JSONDecoder().decode(AuthResponse.self, from: data) else { throw CloudError.decoding }
        apply(idToken: res.idToken, refresh: res.refreshToken, uid: res.localId,
              email: res.email ?? email, expiresIn: res.expiresIn)
        pendingInitialSync = true   // interactive login → pull cloud copy once
    }

    private func refreshIDToken(using refresh: String) async throws {
        guard let key = CloudConfig.apiKey else { throw CloudError.notConfigured }
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(key)")!
        let body = ["grant_type": "refresh_token", "refresh_token": refresh]
        let (data, http) = try await CloudHTTP.postForm(url, body: body)
        guard http.statusCode == 200,
              let res = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            // Refresh token invalid/expired → force re-login.
            signOut()
            throw CloudError.notSignedIn
        }
        apply(idToken: res.id_token, refresh: res.refresh_token, uid: res.user_id,
              email: email ?? "", expiresIn: res.expires_in)
    }

    private func apply(idToken: String, refresh: String, uid: String, email: String, expiresIn: String) {
        self.idToken = idToken
        self.idTokenExpiry = Date().addingTimeInterval(Double(expiresIn) ?? 3600)
        self.refreshToken = refresh
        self.uid = uid
        if !email.isEmpty { self.email = email }
        defaults.set(refresh, forKey: Self.kRefresh)
        defaults.set(uid, forKey: Self.kUID)
        if !email.isEmpty { defaults.set(email, forKey: Self.kEmail) }
    }

    private static func errorCode(from data: Data) -> String {
        (try? JSONDecoder().decode(AuthErrorResponse.self, from: data))?.error.message ?? "UNKNOWN"
    }

    private struct AuthResponse: Decodable {
        let idToken: String; let refreshToken: String; let localId: String
        let email: String?; let expiresIn: String
    }
    private struct RefreshResponse: Decodable {
        let id_token: String; let refresh_token: String; let user_id: String; let expires_in: String
    }
    private struct AuthErrorResponse: Decodable { struct E: Decodable { let message: String }; let error: E }
}

// MARK: - Firestore sync

enum CloudSync {

    /// Pushes ALL local data (one JSON snapshot) up to Firestore, overwriting the
    /// user's cloud copy.
    @MainActor
    static func upload(decks: DeckStore, practice: PracticeStore, chat: ChatHistoryStore,
                       flashcards: FlashcardStore, songs: SongLibraryStore,
                       grammar: GrammarStore, settings: AppSettings) async throws {
        guard CloudConfig.isConfigured else { throw CloudError.notConfigured }
        let token = try await CloudAuth.shared.validIDToken()
        guard let uid = CloudAuth.shared.uid, let project = CloudConfig.projectID else {
            throw CloudError.notSignedIn
        }
        let data = try BackupService.makeData(decks: decks, practice: practice, chat: chat,
                                              flashcards: flashcards, songs: songs, grammar: grammar, settings: settings)
        let json = String(decoding: data, as: UTF8.self)
        let isoNow = ISO8601DateFormatter().string(from: .now)
        let payload: [String: Any] = [
            "fields": [
                "backup": ["stringValue": json],
                "updatedAt": ["timestampValue": isoNow]
            ]
        ]
        var req = URLRequest(url: documentURL(project: project, uid: uid))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (respData, http) = try await URLSession.shared.data(for: req)
        guard let code = (http as? HTTPURLResponse)?.statusCode, code == 200 else {
            throw CloudError.server(CloudHTTP.message(respData))
        }
    }

    /// Pulls the cloud snapshot down and replaces local data. Returns false when
    /// the user has no cloud document yet (nothing to download).
    @MainActor
    @discardableResult
    static func download(decks: DeckStore, practice: PracticeStore, chat: ChatHistoryStore,
                         flashcards: FlashcardStore, songs: SongLibraryStore,
                         grammar: GrammarStore, settings: AppSettings) async throws -> Bool {
        guard CloudConfig.isConfigured else { throw CloudError.notConfigured }
        let token = try await CloudAuth.shared.validIDToken()
        guard let uid = CloudAuth.shared.uid, let project = CloudConfig.projectID else {
            throw CloudError.notSignedIn
        }
        var req = URLRequest(url: documentURL(project: project, uid: uid))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await URLSession.shared.data(for: req)
        let code = (http as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return false }                       // no cloud copy yet
        guard code == 200 else { throw CloudError.server(CloudHTTP.message(data)) }
        guard let doc = try? JSONDecoder().decode(FSDoc.self, from: data),
              let json = doc.fields?.backup?.stringValue,
              let blob = json.data(using: .utf8) else { throw CloudError.decoding }
        try BackupService.restore(data: blob, decks: decks, practice: practice, chat: chat,
                                  flashcards: flashcards, songs: songs, grammar: grammar, settings: settings)
        return true
    }

    private static func documentURL(project: String, uid: String) -> URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents/users/\(uid)")!
    }

    private struct FSDoc: Decodable {
        struct Fields: Decodable { let backup: Value? }
        struct Value: Decodable { let stringValue: String? }
        let fields: Fields?
    }
}

// MARK: - HTTP helpers

enum CloudHTTP {
    static func postJSON(_ url: URL, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    static func postForm(_ url: URL, body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    private static func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CloudError.decoding }
        return (data, http)
    }

    /// Best-effort human message from a Google error response body.
    static func message(_ data: Data) -> String {
        struct G: Decodable { struct E: Decodable { let message: String }; let error: E }
        return (try? JSONDecoder().decode(G.self, from: data))?.error.message
            ?? "Lỗi máy chủ. Kiểm tra mạng / cấu hình Firebase."
    }
}
