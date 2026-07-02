//
//  GrammarHomeView.swift
//  ITBizEnglish
//
//  The Grammar tab is a LIBRARY of the lessons you've made (this is the tab
//  root), with what's due for spaced-repetition review pinned on top. Making a
//  new lesson lives on its own page (GrammarCreateView), reached from the big
//  "Tạo bài học mới" button. Generated lessons auto-save into the library.
//

import SwiftUI

// MARK: - Library (tab root)

struct GrammarLibraryView: View {
    @Bindable var store: GrammarStore
    var mistakes: GrammarMistakeStore
    var feedback: GrammarFeedbackStore
    @State private var route: GrammarRoute?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    NavigationLink {
                        GrammarCreateView(store: store, mistakes: mistakes, feedback: feedback)
                    } label: {
                        Label("Tạo bài học mới", systemImage: "sparkles")
                    }
                    .buttonStyle(.duoPrimary(enabled: true))
                    .padding(.top, Theme.Spacing.xs)

                    if !mistakes.isEmpty { mistakesEntry }
                    if !store.dueForReview.isEmpty { dueSection }

                    if store.lessons.isEmpty {
                        emptyState
                    } else {
                        savedSection
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .navigationTitle("Ngữ pháp")
        .navigationDestination(item: $route) { r in
            GrammarLessonView(route: r, store: store, mistakes: mistakes, feedback: feedback)
        }
    }

    /// Entry into the mistakes bank (error-driven review).
    private var mistakesEntry: some View {
        NavigationLink {
            GrammarMistakesView(mistakes: mistakes, store: store)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.duoRed).frame(width: 46, height: 46)
                    Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lỗi cần ôn").font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk)
                    Text("\(mistakes.count) câu bạn từng trả lời sai")
                        .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.duoSwan)
            }
            .padding(Theme.Spacing.md)
            .duoCard(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Cần ôn hôm nay (\(store.dueForReview.count))", systemImage: "calendar.badge.exclamationmark")
                .font(.headline.weight(.heavy)).foregroundStyle(.duoIndigo)
            ForEach(store.dueForReview) { saved in row(saved, due: true) }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("BÀI HỌC CỦA BẠN (\(store.lessons.count))")
                .font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(store.lessons) { saved in row(saved, due: false) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            AnimatedGIF(name: AnimatedGIF.randomClap()).frame(width: 140, height: 140)
            Text("Chưa có bài học nào").font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Nhập một mẫu ngữ pháp (VD: “I'm getting…”) và để AI soạn cả bài học + luyện tập cho bạn.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    private func row(_ saved: SavedGrammarLesson, due: Bool) -> some View {
        Button {
            route = GrammarRoute(pattern: saved.pattern, request: saved.request,
                                 lesson: saved.lesson, savedID: saved.id)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(saved.lesson.hero.difficultyValue.color).frame(width: 46, height: 46)
                    Image(systemName: "text.book.closed.fill").foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(saved.pattern).font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(1)
                    HStack(spacing: 6) {
                        if let s = saved.bestScore {
                            Text("\(s)đ").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(scoreColor(s)))
                        }
                        Text(due ? "Đến hạn ôn" : saved.nextReviewLabel)
                            .font(.caption.weight(.bold)).foregroundStyle(due ? .duoIndigo : .duoWolf)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.duoSwan)
            }
            .padding(Theme.Spacing.md)
            .duoCard(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation { store.delete(id: saved.id) }
            } label: { Label("Xóa", systemImage: "trash") }
        }
    }

    private func scoreColor(_ s: Int) -> Color { s >= 85 ? .duoGreen : (s >= 60 ? .duoGold : .duoRed) }
}

// MARK: - Create a new lesson (separate page)

struct GrammarCreateView: View {
    @Bindable var store: GrammarStore
    var mistakes: GrammarMistakeStore
    var feedback: GrammarFeedbackStore

    @State private var pattern = ""
    @State private var selectedRequests: Set<String> = []
    @State private var extraRequest = ""
    @State private var generating = false
    @State private var route: GrammarRoute?
    @State private var alert: DuoAlertData?
    @State private var mascot = AnimatedGIF.randomClap()
    @FocusState private var inputFocused: Bool

    static let examples = [
        "I'm getting…", "Used to", "Be going to", "Present perfect",
        "Would rather", "As soon as", "Get used to", "Had better"
    ]
    static let requestOptions = [
        "Giải thích cho người mới", "Tập trung kỹ năng nói", "So sánh với cấu trúc khác",
        "Nhiều ví dụ thực tế", "Luyện IELTS", "Tiếng Anh công sở"
    ]

    private var canGenerate: Bool {
        !pattern.trimmingCharacters(in: .whitespaces).isEmpty && AppConfiguration.hasGeminiKey && !generating
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    intro
                    inputCard
                    requestCard
                    generateButton
                    if !AppConfiguration.hasGeminiKey { noKeyNote }
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            if generating {
                GrammarLoadingOverlay(pattern: pattern.trimmingCharacters(in: .whitespaces))
            }
        }
        .navigationTitle("Tạo bài học")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { r in
            GrammarLessonView(route: r, store: store, mistakes: mistakes, feedback: feedback)
        }
        .duoAlert($alert)
    }

    private var intro: some View {
        HStack(spacing: Theme.Spacing.md) {
            AnimatedGIF(name: mascot).frame(width: 84, height: 84)
            Text("Nhập mẫu ngữ pháp bạn muốn học — AI sẽ soạn cả bài học sinh động + luyện tập riêng.")
                .font(.callout.weight(.bold)).foregroundStyle(.duoInk)
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("MẪU NGỮ PHÁP").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            TextField("VD: I'm getting…, Used to, Be going to", text: $pattern, axis: .vertical)
                .lineLimit(1...3).font(.title3.weight(.bold)).foregroundStyle(.duoInk)
                .focused($inputFocused)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))

            Text("Hoặc chọn nhanh:").font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
            FlowLayout(spacing: 8) {
                ForEach(Self.examples, id: \.self) { ex in
                    Button { pattern = ex; inputFocused = false } label: {
                        Text(ex).font(.subheadline.weight(.bold)).foregroundStyle(.duoIndigo)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.duoIndigo.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var requestCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("YÊU CẦU THÊM (TUỲ CHỌN)").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            FlowLayout(spacing: 8) {
                ForEach(Self.requestOptions, id: \.self) { opt in
                    let on = selectedRequests.contains(opt)
                    Button {
                        Haptics.tap()
                        if on { selectedRequests.remove(opt) } else { selectedRequests.insert(opt) }
                    } label: {
                        Text(opt)
                            .font(.subheadline.weight(.bold)).foregroundStyle(on ? .white : .duoInk)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(on ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.duoPolar)))
                            .overlay(Capsule().strokeBorder(on ? Color.brandEdge : Color.duoSwan, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Khác… (VD: hay nhầm với present continuous)", text: $extraRequest, axis: .vertical)
                .lineLimit(1...3).font(.callout).foregroundStyle(.duoInk)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private var generateButton: some View {
        Button(action: generate) {
            Label("Tạo bài học", systemImage: "sparkles")
        }
        .buttonStyle(.duoPrimary(enabled: canGenerate))
        .disabled(!canGenerate)
    }

    private var noKeyNote: some View {
        Label("Thêm API key trong Cài đặt để dùng tính năng AI.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.bold)).foregroundStyle(.duoRed)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generate() {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        inputFocused = false
        Haptics.tap()
        var parts = Array(selectedRequests)
        let extra = extraRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { parts.append(extra) }
        let request = parts.joined(separator: "; ")

        store.rememberPattern(p)
        generating = true
        alert = nil
        Task {
            do {
                let lesson = try await GrammarAIService().generate(pattern: p, request: request)
                await MainActor.run {
                    generating = false
                    // Auto-save into the library so it shows on the main page.
                    let id = store.save(lesson, pattern: p, request: request)
                    route = GrammarRoute(pattern: p, request: request, lesson: lesson, savedID: id)
                }
            } catch {
                await MainActor.run {
                    generating = false
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Thử lại nhé."
                    alert = DuoAlertData(title: "Không tạo được bài học", message: msg)
                }
            }
        }
    }
}

// MARK: - Mistakes bank (error-driven review)

/// Lists the grammar questions the learner has gotten wrong, grouped by pattern,
/// with a one-tap "re-drill them all" review that clears items as they're
/// answered correctly.
struct GrammarMistakesView: View {
    @Bindable var mistakes: GrammarMistakeStore
    @Bindable var store: GrammarStore

    @State private var run: GrammarPracticeRun?
    @State private var clearAlert: DuoAlertData?

    var body: some View {
        ZStack {
            AppBackground()
            if mistakes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        reviewButton
                        ForEach(mistakes.grouped, id: \.pattern) { group in
                            patternSection(group.pattern, items: group.items)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .navigationTitle("Lỗi cần ôn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !mistakes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        clearAlert = DuoAlertData(title: "Xoá tất cả lỗi?",
                                                  message: "Danh sách lỗi cần ôn sẽ bị xoá hết.",
                                                  confirmTitle: "Xoá hết",
                                                  confirmColor: .duoRed,
                                                  confirmEdge: .duoRedEdge,
                                                  onConfirm: { mistakes.clear() },
                                                  cancelTitle: "Huỷ")
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.duoRed)
                    }
                }
            }
        }
        .navigationDestination(item: $run) { r in
            GrammarPracticeView(route: mistakeRoute, exercises: r.exercises, store: store,
                                savedID: nil, setID: nil, mistakes: mistakes,
                                isMistakeReview: true, sourceLabel: "Ôn lỗi")
        }
        .duoAlert($clearAlert)
    }

    private var mistakeRoute: GrammarRoute {
        GrammarRoute(pattern: "Ôn lỗi ngữ pháp", request: "", lesson: GrammarLesson())
    }

    private var reviewButton: some View {
        Button {
            Haptics.tap()
            run = GrammarPracticeRun(exercises: mistakes.practiceExercises(), contextLabel: "Ôn lỗi")
        } label: {
            Label("Luyện lại tất cả (\(min(mistakes.count, 20)))", systemImage: "play.fill")
        }
        .buttonStyle(.duoPrimary(enabled: true))
        .padding(.top, Theme.Spacing.xs)
    }

    private func patternSection(_ pattern: String, items: [GrammarMistakeEntry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(pattern.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(items) { entry in row(entry) }
        }
    }

    private func row(_ entry: GrammarMistakeEntry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: entry.exercise.kind.icon)
                .font(.subheadline.weight(.bold)).foregroundStyle(.duoRed)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.duoRed.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.exercise.prompt).font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                    .lineLimit(2)
                Text("\(entry.exercise.kindLabel) · sai \(entry.timesWrong) lần")
                    .font(.caption2.weight(.bold)).foregroundStyle(.duoWolf)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation { mistakes.remove(id: entry.id) }
            } label: { Label("Xoá khỏi danh sách", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            AnimatedGIF(name: "happy").frame(width: 150, height: 150)
            Text("Không còn lỗi nào!").font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Những câu bạn trả lời sai khi luyện tập sẽ xuất hiện ở đây để ôn lại.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}
