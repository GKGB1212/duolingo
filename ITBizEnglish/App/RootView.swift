//
//  RootView.swift
//  ITBizEnglish
//
//  Tab container. Stores are created once here and shared.
//   • Translate     — Gemini translator (Save → Self-Translate)
//   • Courses        — Memrise-style decks (learn + review + game)
//   • Self-Translate — write Vietnamese→English, graded by AI
//
//  The bottom bar is a custom Duolingo-style bar: icon-only, with the selected
//  tab lifted into an accent-tinted rounded "pill". All four tabs stay alive
//  (rendered behind each other) so each keeps its scroll/navigation state.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct RootView: View {
    @State private var flashcards = FlashcardStore()   // translation history
    @State private var decks = DeckStore()             // Memrise-style courses
    @State private var practice = PracticeStore()       // self-translate sets
    @State private var chatHistory = ChatHistoryStore() // finished chat sessions
    @State private var grammar = GrammarStore()         // AI grammar lessons
    @State private var grammarMistakes = GrammarMistakeStore() // banked wrong grammar answers
    @State private var grammarFeedback = GrammarFeedbackStore() // lesson ratings (local)
    @State private var settings = AppSettings.shared    // appearance + API keys

    @State private var tab: RootTab = .chat
    @State private var showMore = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // A plain VStack: a ZStack of all tabs (each its own NavigationStack)
        // on top, the custom bar pinned below. We deliberately DON'T use a
        // `TabView`: a TabView with >5 tabs collapses the extras into UIKit's
        // automatic "More" navigation stack, which leaked a spurious back button
        // into the last tabs. Keeping every tab alive here preserves their
        // scroll/nav state, exactly like a tab bar, without that behavior.
        //
        // The bar is a sibling of the content (NOT a `.safeAreaInset`): a
        // `safeAreaInset` applied out here does NOT propagate through the
        // per-tab `NavigationStack`s — NavigationStack resets the safe area to
        // the window's — so content scrolled under the bar. As VStack siblings,
        // the content area simply ends at the bar's top edge, so every screen
        // (tab roots AND pushed detail screens) clears the bar.
        VStack(spacing: 0) {
            ZStack {
                tabContent(.translate)     { NavigationStack { TranslationView(store: flashcards, practice: practice, decks: decks) } }
                tabContent(.chat)          { NavigationStack { ChatHomeView(decks: decks, history: chatHistory) } }
                tabContent(.courses)       { NavigationStack { DecksHomeView(store: decks) } }
                tabContent(.songs)         { SongSearchView() }
                tabContent(.selfTranslate) { NavigationStack { PracticeHomeView(store: practice, decks: decks) } }
                tabContent(.grammar)       { NavigationStack { GrammarLibraryView(store: grammar, mistakes: grammarMistakes, feedback: grammarFeedback) } }
                tabContent(.settings)      { NavigationStack { SettingsView(settings: settings, decks: decks, practice: practice, chatHistory: chatHistory, flashcards: flashcards, grammar: grammar, grammarMistakes: grammarMistakes) } }
            }
            DuoTabBar(selection: $tab, showMore: $showMore)
        }
        // Messenger-style floating quick-lookup bubble, available on every tab.
        .overlay {
            if settings.lookupBubbleEnabled {
                QuickLookupBubble(decks: decks)
            }
        }
        .sheet(isPresented: $showMore) {
            MoreMenuView(selection: $tab)
        }
        .tint(settings.theme.primary)
        .fontDesign(.rounded)
        .preferredColorScheme(settings.appearance.colorScheme)
        // Auto-back-up to the cloud when leaving the app (only if signed in).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, CloudAuth.shared.isSignedIn else { return }
            Task {
                try? await CloudSync.upload(decks: decks, practice: practice, chat: chatHistory,
                                            flashcards: flashcards, songs: .shared, grammar: grammar, grammarMistakes: grammarMistakes, settings: settings)
            }
        }
        // Right after an interactive login, pull the cloud copy down once.
        .task {
            guard CloudAuth.shared.pendingInitialSync else { return }
            CloudAuth.shared.pendingInitialSync = false
            try? await CloudSync.download(decks: decks, practice: practice, chat: chatHistory,
                                          flashcards: flashcards, songs: .shared, grammar: grammar, grammarMistakes: grammarMistakes, settings: settings)
        }
    }

    /// Wraps one tab: shows/enables only the active tab while keeping the others
    /// alive in the background (so each keeps its scroll/navigation state). The
    /// content area is bounded above the bar by the parent VStack, so nothing —
    /// including pushed navigation screens — hides behind the bar.
    @ViewBuilder
    private func tabContent<Content: View>(_ which: RootTab, @ViewBuilder content: () -> Content) -> some View {
        let isActive = which == tab
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

// MARK: - Tabs

enum RootTab: CaseIterable {
    case translate, chat, courses, songs, selfTranslate, grammar, settings

    var title: String {
        switch self {
        case .translate:     return "Dịch"
        case .chat:          return "Chat"
        case .courses:       return "Khoá học"
        case .songs:         return "Bài hát"
        case .selfTranslate: return "Tự dịch"
        case .grammar:       return "Ngữ pháp"
        case .settings:      return "Cài đặt"
        }
    }

    var icon: String {
        switch self {
        case .translate:     return "character.bubble"
        case .chat:          return "bubble.left.and.bubble.right"
        case .courses:       return "rectangle.stack"
        case .songs:         return "music.note"
        case .selfTranslate: return "pencil.and.scribble"
        case .grammar:       return "text.book.closed"
        case .settings:      return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .translate:     return "character.bubble.fill"
        case .chat:          return "bubble.left.and.bubble.right.fill"
        case .courses:       return "rectangle.stack.fill"
        case .songs:         return "music.note.list"
        case .selfTranslate: return "pencil.and.scribble"
        case .grammar:       return "text.book.closed.fill"
        case .settings:      return "gearshape.fill"
        }
    }

    /// Tabs pinned to the bottom bar.
    static let primary: [RootTab] = [.translate, .courses, .selfTranslate]
    /// Tabs tucked into the "•••" More menu so the bar stays uncluttered.
    static let more: [RootTab] = [.chat, .songs, .grammar, .settings]

    /// Longer, friendlier title used in the More menu rows.
    var menuTitle: String {
        switch self {
        case .translate:     return "Dịch"
        case .chat:          return "Chat cùng AI"
        case .courses:       return "Khoá học"
        case .songs:         return "Học với nhạc"
        case .selfTranslate: return "Tự dịch"
        case .grammar:       return "Học ngữ pháp"
        case .settings:      return "Cài đặt"
        }
    }

    /// One-line subtitle for the More menu rows.
    var menuSubtitle: String {
        switch self {
        case .translate:     return "Dịch Việt ⇄ Anh bằng AI"
        case .chat:          return "Luyện nói qua hội thoại AI"
        case .courses:       return "Học từ vựng kiểu Memrise"
        case .songs:         return "Học tiếng Anh qua bài hát"
        case .selfTranslate: return "Tự viết câu, AI chấm điểm"
        case .grammar:       return "Bài học ngữ pháp AI tạo riêng"
        case .settings:      return "API key, sao lưu, giao diện"
        }
    }

    /// Accent color for the colored icon tile in the More menu.
    var menuColor: Color {
        switch self {
        case .translate:     return .duoBlue
        case .chat:          return .duoBlue
        case .courses:       return .duoGold
        case .songs:         return .duoIndigo
        case .selfTranslate: return .duoIndigo
        case .grammar:       return .duoGreen
        case .settings:      return .duoWolf
        }
    }
}

// MARK: - Duolingo-style bottom bar

struct DuoTabBar: View {
    @Binding var selection: RootTab
    /// Opens the "•••" More menu (the overflow of secondary features).
    @Binding var showMore: Bool

    /// Height of the bar's content area (the icon row). The background bleeds
    /// below into the home-indicator area. A bit taller than the system 49pt so
    /// the icons are easier to tap. The bar sits below the content area in the
    /// RootView VStack, so this height is what every tab's content clears.
    static let barHeight: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.primary, id: \.self) { tab in
                item(tab)
                    .frame(maxWidth: .infinity)
            }
            moreButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight, alignment: .top)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.duoSwan).frame(height: 2)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: RootTab) -> some View {
        let on = tab == selection
        return Button {
            guard !on else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = tab }
        } label: {
            pill(icon: on ? tab.selectedIcon : tab.icon, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    /// "•••" button — highlighted while one of the More-menu features is active.
    private var moreButton: some View {
        let on = RootTab.more.contains(selection)
        return Button {
            Haptics.tap()
            showMore = true
        } label: {
            pill(icon: "ellipsis", on: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Khác")
    }

    private func pill(icon: String, on: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(on ? Color.brand : Color.duoHare)
            .frame(width: 54, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? Color.brand.opacity(0.15) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(on ? Color.brand.opacity(0.45) : .clear, lineWidth: 2)
            )
            .scaleEffect(on ? 1 : 0.92)
            .contentShape(Rectangle())
    }
}

// MARK: - "•••" More menu (Duolingo-style)

/// The overflow of secondary features (Chat, Bài hát, Ngữ pháp, Cài đặt) shown
/// as a friendly sheet of big colorful rows so the bottom bar stays uncluttered.
struct MoreMenuView: View {
    @Binding var selection: RootTab
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 0) {
                Text("Khác")
                    .font(.title2.weight(.heavy)).foregroundStyle(.duoInk)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)

                ForEach(RootTab.more, id: \.self) { tab in
                    Button {
                        Haptics.tap()
                        selection = tab
                        dismiss()
                    } label: { row(tab) }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.duoSwan)
                }
                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ tab: RootTab) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tab.menuColor).frame(width: 50, height: 50)
                Image(systemName: tab.selectedIcon)
                    .font(.title3.weight(.bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.menuTitle).font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                Text(tab.menuSubtitle).font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
            }
            Spacer(minLength: 0)
            if tab == selection {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(.brand)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var decks: DeckStore
    var practice: PracticeStore
    var chatHistory: ChatHistoryStore
    var flashcards: FlashcardStore
    var grammar: GrammarStore
    var grammarMistakes: GrammarMistakeStore
    @State private var newProvider: LLMProvider = .gemini
    @State private var newKey = ""
    @State private var showKeyGuide = false

    // Backup / restore (manual cross-device sync).
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var backupMessage: String?
    @State private var backupIsError = false

    /// Identifiable wrapper so the share sheet can be driven by `.sheet(item:)`.
    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    // Cloud sync (Firebase, optional).
    @State private var cloudAuth = CloudAuth.shared
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""
    @State private var cloudBusy = false
    @State private var cloudMessage: String?
    @State private var cloudIsError = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    appearanceCard
                    themeCard
                    voiceCard
                    lookupBubbleCard
                    grammarVerifyCard
                    backupCard
                    cloudCard
                    if let last = settings.lastUsedSummary { lastUsedCard(last) }
                    keysCard
                    addKeyCard
                    if !settings.hasCredential { noKeyWarning }
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showKeyGuide) {
            KeyGuideSheet(highlight: newProvider)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert(backupIsError ? "Lỗi" : "Xong",
               isPresented: Binding(get: { backupMessage != nil },
                                    set: { if !$0 { backupMessage = nil } })) {
            Button("OK") { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
    }

    // MARK: - Backup / restore

    private var backupCard: some View {
        settingsCard("Sao lưu & Đồng bộ", icon: "arrow.triangle.2.circlepath", tint: .duoBlue) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Xuất toàn bộ dữ liệu (bộ từ, bộ câu, lịch sử, bài hát, bài ngữ pháp, API key) ra 1 file, gửi sang máy khác qua AirDrop/Files/iCloud Drive rồi bấm Nhập ở đó.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: exportBackup) {
                        Label("Xuất dữ liệu", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge))

                    Button { showImporter = true } label: {
                        Label("Nhập dữ liệu", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.duo(.duoGreen, edge: .duoGreenEdge))
                }
                Text("⚠️ Nhập sẽ THAY THẾ dữ liệu hiện có trên máy này. File chứa cả API key — chỉ gửi cho chính bạn.")
                    .font(.caption2.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func exportBackup() {
        do {
            let url = try BackupService.writeTempFile(
                decks: decks, practice: practice, chat: chatHistory,
                flashcards: flashcards, songs: .shared, grammar: grammar, grammarMistakes: grammarMistakes, settings: settings)
            shareItem = ShareItem(url: url)
        } catch {
            backupIsError = true
            backupMessage = "Không tạo được file sao lưu."
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let backup = try BackupService.restore(
                    from: url, decks: decks, practice: practice, chat: chatHistory,
                    flashcards: flashcards, songs: .shared, grammar: grammar, grammarMistakes: grammarMistakes, settings: settings)
                backupIsError = false
                backupMessage = "Đã nhập: \(backup.summary)."
            } catch {
                backupIsError = true
                backupMessage = (error as? LocalizedError)?.errorDescription ?? "Không nhập được file này."
            }
        case .failure:
            backupIsError = true
            backupMessage = "Không mở được file."
        }
    }

    // MARK: - Cloud sync (Firebase)

    private var cloudCard: some View {
        settingsCard("Tài khoản đám mây", icon: "icloud.fill", tint: .duoIndigo) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if !CloudConfig.isConfigured {
                    Text("Đồng bộ qua Firebase (miễn phí). Chưa cấu hình: tạo project Firebase, bật Email/Password + Firestore, rồi dán Project ID & Web API key vào Configuration.plist.")
                        .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if cloudAuth.isSignedIn {
                    cloudSignedIn
                } else {
                    cloudSignIn
                }
                if let cloudMessage {
                    Text(cloudMessage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(cloudIsError ? .duoRed : .duoGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var cloudSignIn: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TextField("Email", text: $cloudEmail)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .modifier(CloudFieldStyle())
            SecureField("Mật khẩu (≥ 6 ký tự)", text: $cloudPassword)
                .modifier(CloudFieldStyle())
            HStack(spacing: Theme.Spacing.sm) {
                Button { Task { await authenticate(signUp: false) } } label: {
                    Label("Đăng nhập", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge, enabled: canAuth)).disabled(!canAuth)
                Button { Task { await authenticate(signUp: true) } } label: {
                    Label("Đăng ký", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.duo(.duoGreen, edge: .duoGreenEdge, enabled: canAuth)).disabled(!canAuth)
            }
            if cloudBusy { ProgressView() }
        }
    }

    private var cloudSignedIn: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(cloudAuth.email ?? "Đã đăng nhập", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
            Text("Tự động tải lên đám mây mỗi khi bạn rời app. Hoặc làm thủ công:")
                .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
            HStack(spacing: Theme.Spacing.sm) {
                Button { Task { await runSync(upload: true) } } label: {
                    Label("Tải lên", systemImage: "icloud.and.arrow.up")
                        .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge))
                Button { Task { await runSync(upload: false) } } label: {
                    Label("Tải về", systemImage: "icloud.and.arrow.down")
                        .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.duo(.duoGreen, edge: .duoGreenEdge))
            }
            .disabled(cloudBusy)
            Button { cloudAuth.signOut(); cloudMessage = nil } label: {
                Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.duoRed)
            }
            .buttonStyle(.plain)
            if cloudBusy {
                HStack(spacing: 6) { ProgressView(); Text("Đang đồng bộ…").font(.caption).foregroundStyle(.duoWolf) }
            }
        }
    }

    private var canAuth: Bool {
        !cloudBusy && cloudEmail.contains("@") && cloudPassword.count >= 6
    }

    @MainActor
    private func authenticate(signUp: Bool) async {
        cloudBusy = true; cloudMessage = nil
        do {
            if signUp { try await cloudAuth.signUp(email: cloudEmail, password: cloudPassword) }
            else { try await cloudAuth.signIn(email: cloudEmail, password: cloudPassword) }
            cloudPassword = ""
            cloudIsError = false
            cloudMessage = "Đã đăng nhập. Bấm “Tải lên” để lưu dữ liệu lên đám mây, hoặc “Tải về” để lấy dữ liệu đã lưu."
        } catch {
            cloudIsError = true
            cloudMessage = (error as? LocalizedError)?.errorDescription ?? "Đăng nhập thất bại."
        }
        cloudBusy = false
    }

    @MainActor
    private func runSync(upload: Bool) async {
        cloudBusy = true; cloudMessage = nil
        do {
            if upload {
                try await CloudSync.upload(decks: decks, practice: practice, chat: chatHistory,
                                           flashcards: flashcards, songs: .shared, grammar: grammar, grammarMistakes: grammarMistakes, settings: settings)
                cloudIsError = false
                cloudMessage = "Đã tải toàn bộ dữ liệu lên đám mây."
            } else {
                let existed = try await CloudSync.download(decks: decks, practice: practice, chat: chatHistory,
                                                           flashcards: flashcards, songs: .shared, grammar: grammar, grammarMistakes: grammarMistakes, settings: settings)
                cloudIsError = !existed
                cloudMessage = existed ? "Đã tải dữ liệu từ đám mây về máy này."
                                       : "Trên đám mây chưa có dữ liệu. Hãy “Tải lên” trước."
            }
        } catch {
            cloudIsError = true
            cloudMessage = (error as? LocalizedError)?.errorDescription ?? "Đồng bộ thất bại."
        }
        cloudBusy = false
    }

    // MARK: Cards

    private var appearanceCard: some View {
        settingsCard("Giao diện", icon: "paintpalette.fill", tint: .duoBlue) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(AppSettings.Appearance.allCases) { mode in
                    let on = settings.appearance == mode
                    Button {
                        withAnimation(.snappy) { settings.appearance = mode }
                    } label: {
                        Text(mode.label)
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(on ? .white : .duoInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.duoPolar))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(on ? Color.brandEdge : Color.duoSwan, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var themeCard: some View {
        settingsCard("Màu chủ đạo", icon: "swatchpalette.fill", tint: .duoIndigo) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: Theme.Spacing.md) {
                ForEach(AppSettings.AppTheme.allCases) { theme in
                    let on = settings.theme == theme
                    Button { withAnimation(.snappy) { settings.theme = theme } } label: {
                        VStack(spacing: 6) {
                            Circle().fill(theme.primary)
                                .frame(width: 46, height: 46)
                                .overlay(Circle().strokeBorder(Color.duoInk.opacity(on ? 0.9 : 0), lineWidth: 3))
                                .overlay {
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.heavy)).foregroundStyle(.white)
                                    }
                                }
                            Text(theme.label).font(.caption2.weight(.bold))
                                .foregroundStyle(on ? .duoInk : .duoWolf)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var voiceCard: some View {
        settingsCard("Giọng đọc", icon: "waveform", tint: .duoGreen) {
            NavigationLink {
                VoicePickerView(settings: settings)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentVoiceTitle)
                            .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                        Text(currentVoiceSubtitle)
                            .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.duoHare)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
            }
            .buttonStyle(.plain)
        }
    }

    private var resolvedVoice: AVSpeechSynthesisVoice? { EnglishVoices.resolved() }

    private var currentVoiceTitle: String {
        guard let v = resolvedVoice else { return "Mặc định" }
        return v.name
    }

    private var currentVoiceSubtitle: String {
        guard let v = resolvedVoice else { return "Giọng hệ thống" }
        let auto = settings.voiceIdentifier == nil ? " · Tự động" : ""
        return "Tiếng Anh \(EnglishVoices.accentLabel(v.language)) · \(EnglishVoices.qualityLabel(v.quality))\(auto)"
    }

    private var lookupBubbleCard: some View {
        settingsCard("Bóng tra cứu nhanh", icon: "character.book.closed.fill", tint: .duoGreen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Toggle(isOn: $settings.lookupBubbleEnabled) {
                    Text("Hiện bóng nổi để tra từ")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                }
                .tint(.brand)
                Text("Bóng nổi quanh màn hình — chạm để tra nhanh Việt ⇄ Anh, lưu vào bộ từ hoặc copy. Kéo bóng tới mép nào cũng được.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var grammarVerifyCard: some View {
        settingsCard("Kiểm tra ngữ pháp bằng AI", icon: "checkmark.shield.fill", tint: .duoIndigo) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Toggle(isOn: $settings.verifyGrammar) {
                    Text("Rà soát đáp án trước khi hiện")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                }
                .tint(.brand)
                Text("Khi tạo bài ngữ pháp, AI sẽ rà lại đáp án các bài tập để tránh dạy sai. Tốn thêm 1 lượt gọi mỗi lần tạo — tắt đi nếu muốn tiết kiệm quota (vẫn luôn kiểm tra cấu trúc bài tập).")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lastUsedCard(_ last: String) -> some View {
        settingsCard("Lần gọi AI gần nhất", icon: "sparkles", tint: .duoGreen) {
            Label(last, systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.bold)).foregroundStyle(.duoGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var keysCard: some View {
        settingsCard("API keys", icon: "key.fill", tint: .duoGold) {
            VStack(spacing: Theme.Spacing.sm) {
                if settings.credentials.isEmpty {
                    Text("Chưa có key nào được thêm.")
                        .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(settings.credentials.enumerated()), id: \.element.id) { index, cred in
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "key.fill").foregroundStyle(.duoGold)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cred.provider.label).font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                                Text(masked(cred.key)).font(.caption.monospaced()).foregroundStyle(.duoWolf)
                            }
                            Spacer()
                            Button {
                                withAnimation { settings.removeCredentials(at: IndexSet(integer: index)) }
                            } label: {
                                Image(systemName: "trash.fill").foregroundStyle(.duoRed)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(Theme.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                    }
                }
                Text(footerText)
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var addKeyCard: some View {
        settingsCard("Thêm key", icon: "plus.circle.fill", tint: .duoGreen) {
            VStack(spacing: Theme.Spacing.sm) {
                Picker("Nhà cung cấp", selection: $newProvider) {
                    ForEach(LLMProvider.allCases) { p in Text(p.label).tag(p) }
                }
                .pickerStyle(.menu).tint(.brand)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Dán API key…", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))

                    Button {
                        withAnimation { settings.addCredential(provider: newProvider, key: newKey); newKey = "" }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title)
                            .foregroundStyle(newKey.trimmingCharacters(in: .whitespaces).isEmpty ? .duoHare : .duoGreen)
                    }
                    .buttonStyle(.plain)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Button { showKeyGuide = true } label: {
                    Label("Hướng dẫn lấy key miễn phí", systemImage: "questionmark.circle.fill")
                        .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge))

                Text("Lấy key miễn phí tại \(newProvider.keyHint). Model mặc định: \(newProvider.defaultModel).")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var noKeyWarning: some View {
        Label("Chưa có key nào — các tính năng AI sẽ bị khóa.", systemImage: "exclamationmark.triangle.fill")
            .font(.callout.weight(.bold)).foregroundStyle(.duoRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Color.duoWrongFill))
    }

    // MARK: Card chrome

    @ViewBuilder
    private func settingsCard<Content: View>(_ title: String, icon: String, tint: Color,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
                Text(title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
            }
            content()
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    /// Shows only the first/last few characters so a key isn't fully exposed.
    private func masked(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return key.prefix(4) + "••••" + key.suffix(4)
    }

    private var footerText: String {
        let count = settings.allCredentials.count
        var base = "Thêm nhiều key (nhiều nhà cung cấp được) để app tự xoay vòng + tự nhảy sang key khác khi 1 key hết hạn mức."
        if count > 0 {
            base += " Đang dùng \(count) key."
        }
        return base
    }
}

// MARK: - Voice picker

/// Lists the English text-to-speech voices installed on the device, grouped by
/// accent. Tap a voice to hear a sample and make it the app's reading voice.
struct VoicePickerView: View {
    @Bindable var settings: AppSettings
    @State private var speech = SpeechSynthesizer()

    private let sample = "Hello, let's practice English together."

    /// Installed English voices grouped by language code (accent), each group
    /// sorted best-quality first.
    private var groups: [(language: String, voices: [AVSpeechSynthesisVoice])] {
        let byLanguage = Dictionary(grouping: EnglishVoices.all(), by: { $0.language })
        return byLanguage
            .map { (language: $0.key, voices: $0.value) }
            .sorted { $0.language < $1.language }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    autoCard
                    ForEach(groups, id: \.language) { group in
                        accentSection(group.language, voices: group.voices)
                    }
                    hintCard
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Giọng đọc")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speech.stop() }
    }

    // "Tự động" — let the app pick the best voice.
    private var autoCard: some View {
        let on = settings.voiceIdentifier == nil
        return Button {
            withAnimation(.snappy) { settings.voiceIdentifier = nil }
            if let best = EnglishVoices.best() {
                speech.preview(sample, voice: best, id: "auto")
            }
        } label: {
            row(title: "Tự động (tốt nhất)",
                subtitle: "App tự chọn giọng tiếng Anh chất lượng cao nhất đã cài.",
                selected: on, speaking: speech.speakingID == "auto")
        }
        .buttonStyle(.plain)
    }

    private func accentSection(_ language: String, voices: [AVSpeechSynthesisVoice]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Tiếng Anh \(EnglishVoices.accentLabel(language))")
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoWolf)
                .padding(.leading, 4)
            ForEach(voices, id: \.identifier) { voice in
                Button {
                    withAnimation(.snappy) { settings.voiceIdentifier = voice.identifier }
                    speech.preview(sample, voice: voice, id: voice.identifier)
                } label: {
                    row(title: voice.name,
                        subtitle: EnglishVoices.qualityLabel(voice.quality),
                        selected: settings.voiceIdentifier == voice.identifier,
                        speaking: speech.speakingID == voice.identifier)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(title: String, subtitle: String, selected: Bool, speaking: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: speaking ? "speaker.wave.2.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                .font(.title3.weight(.bold))
                .foregroundStyle(speaking ? AnyShapeStyle(Color.brand)
                                          : (selected ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.duoHare)))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
            }
            Spacer()
            Image(systemName: "play.circle").font(.title2).foregroundStyle(.duoWolf)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(selected ? Color.brand.opacity(0.12) : Color.duoPolar))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(selected ? Color.brand : Color.duoSwan, lineWidth: 2))
    }

    private var hintCard: some View {
        Label {
            Text("Muốn giọng tự nhiên hơn? Vào **Cài đặt iOS ▸ Trợ năng ▸ Nội dung nói ▸ Giọng nói ▸ English** rồi tải các giọng **Nâng cao / Cao cấp** (miễn phí). Tải xong, quay lại đây để chọn.")
        } icon: {
            Image(systemName: "lightbulb.fill").foregroundStyle(.duoGold)
        }
        .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

/// Rounded text-field chrome for the cloud sign-in fields.
private struct CloudFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
    }
}

// MARK: - Auth gate (login required before entering the app)

/// Root of the app: shows the login screen until the user is signed in. When
/// Firebase isn't configured yet the app stays usable (login can't be enforced
/// without a backend).
struct AuthGateView: View {
    @State private var auth = CloudAuth.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        Group {
            if auth.isSignedIn || !CloudConfig.isConfigured {
                RootView()
            } else {
                LoginView()
            }
        }
        .tint(settings.theme.primary)
        .fontDesign(.rounded)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

/// Email/password sign-in shown before the app when cloud sync is configured.
struct LoginView: View {
    @State private var auth = CloudAuth.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 56)).foregroundStyle(.brand)
                        Text("ITBizEnglish").font(.largeTitle.weight(.heavy)).foregroundStyle(.duoInk)
                        Text(isSignUp ? "Tạo tài khoản để lưu & đồng bộ dữ liệu của bạn"
                                      : "Đăng nhập để tiếp tục")
                            .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    if CloudConfig.isConfigured { formCard } else { notConfigured }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var formCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .focused($focus, equals: .email)
                .submitLabel(.next).onSubmit { focus = .password }
                .modifier(CloudFieldStyle())
            SecureField("Mật khẩu (≥ 6 ký tự)", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(.go).onSubmit { Task { await submit() } }
                .modifier(CloudFieldStyle())

            if let error {
                Text(error).font(.caption.weight(.bold)).foregroundStyle(.duoRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { Task { await submit() } } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if busy { ProgressView().tint(.white) }
                    Text(isSignUp ? "Đăng ký" : "Đăng nhập").font(.headline.weight(.heavy))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.duoPrimary(enabled: canSubmit))
            .disabled(!canSubmit)

            Button { withAnimation { isSignUp.toggle(); error = nil } } label: {
                Text(isSignUp ? "Đã có tài khoản? Đăng nhập"
                              : "Chưa có tài khoản? Đăng ký")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.lg)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var notConfigured: some View {
        Text("Chưa cấu hình Firebase. Thêm FIREBASE_PROJECT_ID và FIREBASE_API_KEY vào Configuration.plist rồi mở lại app.")
            .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
            .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var canSubmit: Bool { !busy && email.contains("@") && password.count >= 6 }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        focus = nil
        busy = true; error = nil
        do {
            if isSignUp { try await auth.signUp(email: email, password: password) }
            else { try await auth.signIn(email: email, password: password) }
            // isSignedIn flips → AuthGateView swaps in the app.
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Thất bại. Thử lại."
        }
        busy = false
    }
}

// MARK: - API-key gate (a key is required before entering the app)

/// Root gate: the app needs at least one AI key to work. Until the user adds
/// one (on the onboarding screen), they can't enter the app. Observing
/// `AppSettings.shared` makes this flip to the app the moment a key is added.
struct KeyGateView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Group {
            if settings.hasCredential {
                RootView()
            } else {
                KeyOnboardingView(settings: settings)
            }
        }
        .tint(settings.theme.primary)
        .fontDesign(.rounded)
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

/// First-launch screen shown when no API key exists yet. Explains why a key is
/// needed, lets the user paste at least one token, and links to a Duolingo-style
/// step-by-step guide for getting a free key from each provider.
struct KeyOnboardingView: View {
    @Bindable var settings: AppSettings

    @State private var provider: LLMProvider = .gemini
    @State private var key = ""
    @State private var showGuide = false
    @FocusState private var keyFocused: Bool

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmedKey.isEmpty }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    addCard
                    guideButton
                    reassurance
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showGuide) { KeyGuideSheet(highlight: provider) }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Color.brand.opacity(0.15)).frame(width: 92, height: 92)
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 40, weight: .bold)).foregroundStyle(.brand)
            }
            Text("Thêm API key để bắt đầu")
                .font(.title.weight(.heavy)).foregroundStyle(.duoInk)
                .multilineTextAlignment(.center)
            Text("ITBizEnglish dùng AI để dịch, chấm câu và trò chuyện. Bạn cần ít nhất **1 API key MIỄN PHÍ** của riêng mình. Lấy chỉ mất khoảng 1 phút.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var addCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.duoGreen))
                Text("Thêm key").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
            }

            Picker("Nhà cung cấp", selection: $provider) {
                ForEach(LLMProvider.allCases) { p in Text(p.label).tag(p) }
            }
            .pickerStyle(.menu).tint(.brand)
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Dán API key…", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyFocused)
                .font(.callout.monospaced())
                .submitLabel(.go).onSubmit(add)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))

            Button(action: add) {
                Label("Thêm key & vào app", systemImage: "arrow.right.circle.fill")
                    .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.duoPrimary(enabled: canAdd))
            .disabled(!canAdd)

            Text("Lấy key miễn phí tại \(provider.keyHint)")
                .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var guideButton: some View {
        Button { showGuide = true } label: {
            Label("Hướng dẫn lấy key miễn phí", systemImage: "questionmark.circle.fill")
                .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge))
    }

    private var reassurance: some View {
        Label {
            Text("Key được lưu **riêng trên máy bạn** và chỉ gửi tới đúng nhà cung cấp AI bạn chọn. Sau này bạn có thể thêm nhiều key trong Cài đặt để app tự xoay vòng khi 1 key hết hạn mức.")
        } icon: {
            Image(systemName: "lock.shield.fill").foregroundStyle(.duoGreen)
        }
        .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func add() {
        guard canAdd else { return }
        keyFocused = false
        Haptics.tap()
        // Adding the first credential flips `hasCredential` → the gate swaps in
        // the app automatically.
        withAnimation { settings.addCredential(provider: provider, key: key) }
        key = ""
    }
}

// MARK: - Duolingo-style "how to get a key" guide

/// A friendly, Duolingo-styled popup that walks through getting a free API key
/// for each provider, with numbered steps and a button that opens the provider's
/// sign-up page directly. Opened from the onboarding gate and from Settings.
struct KeyGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Provider to surface first (e.g. the one currently picked).
    var highlight: LLMProvider? = nil

    private var orderedProviders: [LLMProvider] {
        guard let h = highlight else { return LLMProvider.allCases }
        return [h] + LLMProvider.allCases.filter { $0 != h }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        intro
                        ForEach(orderedProviders) { provider in
                            providerCard(provider)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Lấy API key miễn phí")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.heavy)
                }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.bold)).foregroundStyle(.duoGold)
            Text("App dùng AI miễn phí của các nhà cung cấp dưới đây. Bạn **chỉ cần 1 key** là đủ. Chọn 1 nhà cung cấp (khuyên dùng Google Gemini), làm theo các bước rồi quay lại dán key.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func providerCard(_ provider: LLMProvider) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header: colored badge + name (+ recommended chip) + blurb.
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "key.fill")
                    .font(.headline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(provider.tint))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.label).font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                        if provider.isRecommended { recommendedChip }
                    }
                    Text(provider.blurb)
                        .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Numbered steps.
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(provider.keySteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(provider.tint))
                        Text(step)
                            .font(.subheadline.weight(.medium)).foregroundStyle(.duoInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Open the provider's key page.
            Button { openURL(provider.signupURL) } label: {
                Label("Mở trang lấy key", systemImage: "arrow.up.right.square.fill")
                    .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.duo(provider.tint, edge: provider.tintEdge))

            Text(provider.keyHint)
                .font(.caption2.monospaced()).foregroundStyle(.duoWolf)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var recommendedChip: some View {
        Text("Khuyên dùng")
            .font(.caption2.weight(.heavy)).foregroundStyle(.duoGreen)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.duoGreen.opacity(0.15)))
    }
}

#Preview {
    KeyGateView()
}
