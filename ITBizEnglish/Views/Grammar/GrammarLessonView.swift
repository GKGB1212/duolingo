//
//  GrammarLessonView.swift
//  ITBizEnglish
//
//  The generated grammar lesson, shown as a stack of bite-size Duolingo cards —
//  one concept per card, big spacing, colorful badges — ending in a CTA to start
//  practice. "Related grammar" chips push a freshly generated lesson onto the
//  same navigation stack (recursive, one-click). Also defines the reusable
//  pieces shared with the practice summary: the loading overlay, the 30-second
//  summary card, and the flashcard deck.
//

import SwiftUI

struct GrammarLessonView: View {
    let route: GrammarRoute
    @Bindable var store: GrammarStore
    /// Missed questions from practice are banked here.
    var mistakes: GrammarMistakeStore
    /// Lesson ratings ("this lesson is off") are logged here.
    var feedback: GrammarFeedbackStore

    @State private var speech = SpeechSynthesizer()
    @State private var savedID: UUID?
    @State private var showSetup = false
    @State private var practiceRun: GrammarPracticeRun?

    // Regeneration + feedback.
    @State private var liveLesson: GrammarLesson?   // overrides route.lesson once regenerated
    @State private var regenerating = false
    @State private var showFeedback = false

    // Recursive "related grammar" navigation.
    @State private var relatedRoute: GrammarRoute?
    @State private var generatingRelated = false
    @State private var relatedAlert: DuoAlertData?

    /// The lesson currently shown — the regenerated one if any, else the route's.
    private var lesson: GrammarLesson { liveLesson ?? route.lesson }
    /// A route carrying the *current* lesson (so practice uses regenerated content).
    private var currentRoute: GrammarRoute {
        GrammarRoute(pattern: route.pattern, request: route.request, lesson: lesson, savedID: route.savedID)
    }
    private var isSaved: Bool { savedID != nil || store.contains(pattern: route.pattern) }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    heroCard
                    meaningCard
                    structureCard
                    if !lesson.visual.steps.isEmpty { visualCard }
                    if !lesson.usage.isEmpty { usageCard }
                    if !lesson.collocations.isEmpty { collocationsCard }
                    if !lesson.mistakes.isEmpty { mistakesCard }
                    if !lesson.comparison.rows.isEmpty || !lesson.comparison.otherName.isEmpty { comparisonCard }

                    practiceCTA

                    if !lesson.relatedGrammar.isEmpty { relatedCard }
                }
                .padding(Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
            if generatingRelated {
                GrammarLoadingOverlay(pattern: relatedPatternInFlight)
            }
            if regenerating {
                GrammarLoadingOverlay(pattern: route.pattern)
            }
        }
        .navigationTitle("Bài học")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleSave() } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? .brand : .duoWolf)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { regenerate() } label: {
                        Label("Tạo lại bài học", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { markGoodLesson() } label: {
                        Label("Bài học tốt 👍", systemImage: "hand.thumbsup")
                    }
                    Button(role: .destructive) { showFeedback = true } label: {
                        Label("Báo lỗi bài học", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.duoWolf)
                }
                .disabled(regenerating)
            }
        }
        .navigationDestination(item: $practiceRun) { run in
            GrammarPracticeView(route: currentRoute, exercises: run.exercises, store: store,
                                savedID: savedIDForPractice, setID: run.setID,
                                mistakes: mistakes, sourceLabel: run.contextLabel)
        }
        .sheet(isPresented: $showFeedback) {
            GrammarFeedbackSheet(pattern: route.pattern) { reasons, note, regen in
                feedback.add(GrammarLessonFeedback(pattern: route.pattern, positive: false,
                                                   reasons: reasons, note: note))
                if regen {
                    let extra = [reasons.joined(separator: ", "), note]
                        .filter { !$0.isEmpty }.joined(separator: ". ")
                    regenerate(extra: extra.isEmpty ? "" : "Sửa các vấn đề sau ở bản trước: \(extra)")
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            GrammarPracticeSetupSheet(pattern: route.pattern, request: route.request,
                                      defaultExercises: lesson.exercises, store: store,
                                      savedID: savedIDForPractice) { exercises, label, setID in
                // Let the sheet finish dismissing before pushing the runner.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    practiceRun = GrammarPracticeRun(exercises: exercises, setID: setID, contextLabel: label)
                }
            }
        }
        .navigationDestination(item: $relatedRoute) { r in
            GrammarLessonView(route: r, store: store, mistakes: mistakes, feedback: feedback)
        }
        .duoAlert($relatedAlert)
        .onAppear {
            if savedID == nil, store.contains(pattern: route.pattern) {
                savedID = store.lessons.first { $0.pattern.caseInsensitiveCompare(route.pattern) == .orderedSame }?.id
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        let hero = lesson.hero
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                badge(hero.difficultyValue.label, color: hero.difficultyValue.color)
                chip(hero.category, icon: hero.categoryIcon, color: hero.categoryColor)
                chip(hero.time, icon: "clock.fill", color: .duoWolf)
                Spacer(minLength: 0)
            }
            Text(hero.pattern.isEmpty ? route.pattern : hero.pattern)
                .font(.largeTitle.weight(.heavy)).foregroundStyle(.duoInk)
                .minimumScaleFactor(0.6).lineLimit(2)
            if !hero.quickMeaning.isEmpty {
                Label(hero.quickMeaning, systemImage: "lightbulb.fill")
                    .font(.callout.weight(.bold)).foregroundStyle(.duoWolf)
            }
            if !hero.example.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text("“\(hero.example)”")
                            .font(.title3.weight(.heavy)).foregroundStyle(.brand)
                        Spacer(minLength: 0)
                        speakButton(hero.example, id: "hero")
                    }
                    if !hero.exampleVi.isEmpty {
                        Text(hero.exampleVi).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf)
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.brand.opacity(0.12)))
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    // MARK: - Meaning

    private var meaningCard: some View {
        sectionCard("Ý nghĩa", icon: "text.bubble.fill", tint: .duoBlue, number: 1) {
            VStack(spacing: Theme.Spacing.sm) {
                meaningRow("Là gì?", lesson.meaning.whatItMeans, icon: "questionmark.circle.fill", tint: .duoBlue)
                meaningRow("Khi nào dùng?", lesson.meaning.whenToUse, icon: "checkmark.circle.fill", tint: .duoGreen)
                meaningRow("Khi nào KHÔNG dùng?", lesson.meaning.whenNotToUse, icon: "xmark.circle.fill", tint: .duoRed)
            }
        }
    }

    private func meaningRow(_ title: String, _ body: String, icon: String, tint: Color) -> some View {
        Group {
            if !body.isEmpty {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: icon).font(.title3).foregroundStyle(tint).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                        Text(body).font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
            }
        }
    }

    // MARK: - Structure

    private var structureCard: some View {
        sectionCard("Cấu trúc", icon: "square.stack.3d.up.fill", tint: .duoIndigo, number: 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !lesson.structure.formula.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(lesson.structure.formula.enumerated()), id: \.offset) { i, token in
                            HStack(spacing: 8) {
                                if i > 0 { Text("+").font(.headline.weight(.heavy)).foregroundStyle(.duoWolf) }
                                Text(token)
                                    .font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.duoIndigo))
                            }
                        }
                    }
                }
                ForEach(Array(lesson.structure.examples.enumerated()), id: \.offset) { _, ex in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.duoIndigo)
                        Text(ex).font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        speakButton(ex, id: "struct-\(ex.hashValue)")
                    }
                }
            }
        }
    }

    // MARK: - Visual chain

    private var visualCard: some View {
        sectionCard("Hình dung", icon: "eye.fill", tint: .duoGreen, number: 3) {
            VStack(spacing: 6) {
                if !lesson.visual.title.isEmpty {
                    Text(lesson.visual.title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(lesson.visual.steps.enumerated()), id: \.offset) { i, step in
                    VStack(spacing: 6) {
                        Text(step)
                            .font(.title3.weight(.heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(stepColor(i, of: lesson.visual.steps.count)))
                        if i < lesson.visual.steps.count - 1 {
                            Image(systemName: "arrow.down").font(.headline.weight(.heavy)).foregroundStyle(.duoWolf)
                        }
                    }
                }
                if !lesson.visual.caption.isEmpty {
                    Text(lesson.visual.caption).font(.subheadline.weight(.medium)).foregroundStyle(.duoWolf)
                        .multilineTextAlignment(.center).padding(.top, 4)
                }
            }
        }
    }

    private func stepColor(_ i: Int, of n: Int) -> Color {
        guard n > 1 else { return .duoGreen }
        let t = Double(i) / Double(n - 1)
        return Color(hue: 0.33 - 0.33 * t * 0.55, saturation: 0.7, brightness: 0.85)
    }

    // MARK: - Usage

    private var usageCard: some View {
        sectionCard("Khi nào dùng", icon: "list.bullet.rectangle.fill", tint: .duoGold, number: 4) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(lesson.usage) { u in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: u.icon).font(.title3).foregroundStyle(.duoGold).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.context.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                            Text(u.sentence).font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                        }
                        Spacer(minLength: 0)
                        speakButton(u.sentence, id: "use-\(u.id)")
                    }
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
                }
            }
        }
    }

    // MARK: - Collocations

    private var collocationsCard: some View {
        sectionCard("Cụm thường gặp", icon: "tag.fill", tint: .duoBlue, number: 5) {
            FlowLayout(spacing: 8) {
                ForEach(Array(lesson.collocations.enumerated()), id: \.offset) { _, phrase in
                    Button { speech.speak(phrase, id: "col-\(phrase.hashValue)") } label: {
                        Text(phrase)
                            .font(.subheadline.weight(.bold)).foregroundStyle(.duoInk)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.duoBlue.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(Color.duoBlue.opacity(0.35), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Mistakes

    private var mistakesCard: some View {
        sectionCard("Lỗi thường gặp", icon: "exclamationmark.triangle.fill", tint: .duoRed, number: 6) {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(lesson.mistakes) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(m.wrong, systemImage: "xmark.circle.fill")
                            .font(.callout.weight(.bold)).foregroundStyle(.duoWrongText)
                        Label(m.correct, systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.bold)).foregroundStyle(.duoOkText)
                        if !m.explanation.isEmpty {
                            Text(m.explanation).font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
                }
            }
        }
    }

    // MARK: - Comparison

    private var comparisonCard: some View {
        let cmp = lesson.comparison
        return sectionCard("So sánh", icon: "arrow.left.arrow.right.circle.fill", tint: .duoIndigo, number: 7) {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text(cmp.thisLabel.isEmpty ? route.pattern : cmp.thisLabel)
                        .font(.subheadline.weight(.heavy)).foregroundStyle(.duoIndigo)
                        .frame(maxWidth: .infinity)
                    Text("vs").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                    Text(cmp.otherLabel.isEmpty ? cmp.otherName : cmp.otherLabel)
                        .font(.subheadline.weight(.heavy)).foregroundStyle(.duoBlue)
                        .frame(maxWidth: .infinity)
                }
                ForEach(cmp.rows) { row in
                    VStack(spacing: 4) {
                        if !row.aspect.isEmpty {
                            Text(row.aspect.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(row.thisValue).font(.caption.weight(.bold)).foregroundStyle(.duoInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle().fill(Color.duoSwan).frame(width: 1.5, height: 28)
                            Text(row.otherValue).font(.caption.weight(.bold)).foregroundStyle(.duoInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                }
                if !cmp.summary.isEmpty {
                    Label(cmp.summary, systemImage: "sparkles")
                        .font(.caption.weight(.bold)).foregroundStyle(.duoIndigo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Practice CTA

    private var practiceCTA: some View {
        Button { Haptics.tap(); showSetup = true } label: {
            Label("Luyện tập", systemImage: "play.fill")
        }
        .buttonStyle(.duoPrimary(enabled: true))
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Related grammar

    private var relatedCard: some View {
        sectionCard("Ngữ pháp liên quan", icon: "point.3.connected.trianglepath.dotted", tint: .duoGreen, number: nil) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Học tiếp một mẫu liên quan — chạm để tạo bài học mới.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                FlowLayout(spacing: 8) {
                    ForEach(Array(lesson.relatedGrammar.enumerated()), id: \.offset) { _, pat in
                        Button { openRelated(pat) } label: {
                            HStack(spacing: 6) {
                                Text(pat).font(.subheadline.weight(.heavy))
                                Image(systemName: "arrow.right.circle.fill").font(.caption)
                            }
                            .foregroundStyle(.duoGreen)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.duoGreen.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(Color.duoGreen.opacity(0.4), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(generatingRelated)
                    }
                }
            }
        }
    }

    // MARK: - Section chrome

    private func sectionHeader(_ title: String, icon: String, tint: Color, number: Int? = nil) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
            Text(title).font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
            Spacer()
            if let number {
                Text("\(number)").font(.caption.weight(.heavy)).foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tint.opacity(0.15)))
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, icon: String, tint: Color, number: Int?,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title, icon: icon, tint: tint, number: number)
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color))
    }
    private func chip(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.heavy)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
    }
    private func speakButton(_ text: String, id: String) -> some View {
        Button { speech.speak(text, id: id) } label: {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.duoBlue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var savedIDForPractice: UUID? { savedID ?? route.savedID }

    private func toggleSave() {
        Haptics.tap()
        if let id = savedIDForPractice ?? store.lessons.first(where: { $0.pattern.caseInsensitiveCompare(route.pattern) == .orderedSame })?.id {
            store.delete(id: id)
            savedID = nil
        } else {
            savedID = store.save(lesson, pattern: route.pattern, request: route.request)
        }
    }

    @State private var relatedPatternInFlight = ""

    /// Regenerates the whole lesson (optionally steering the model with `extra`
    /// guidance from a bad-lesson report), updates the saved copy in place, and
    /// swaps the view to the fresh content.
    private func regenerate(extra: String = "") {
        guard !regenerating else { return }
        Haptics.tap()
        regenerating = true
        let req = [route.request, extra].filter { !$0.isEmpty }.joined(separator: "; ")
        Task {
            do {
                let l = try await GrammarAIService().generate(pattern: route.pattern, request: req)
                await MainActor.run {
                    regenerating = false
                    withAnimation { liveLesson = l }
                    savedID = store.save(l, pattern: route.pattern, request: route.request)
                }
            } catch {
                await MainActor.run {
                    regenerating = false
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Thử lại nhé."
                    relatedAlert = DuoAlertData(title: "Không tạo lại được bài học", message: msg)
                }
            }
        }
    }

    private func markGoodLesson() {
        Haptics.tap()
        feedback.add(GrammarLessonFeedback(pattern: route.pattern, positive: true))
        relatedAlert = DuoAlertData(title: "Cảm ơn bạn! 🎉",
                                    message: "Phản hồi giúp cải thiện chất lượng các bài học.")
    }

    private func openRelated(_ pattern: String) {
        guard !generatingRelated else { return }
        Haptics.tap()
        relatedPatternInFlight = pattern
        generatingRelated = true
        Task {
            do {
                let l = try await GrammarAIService().generate(pattern: pattern, request: route.request)
                await MainActor.run {
                    generatingRelated = false
                    let id = store.save(l, pattern: pattern, request: route.request)   // auto-save to library
                    relatedRoute = GrammarRoute(pattern: pattern, request: route.request, lesson: l, savedID: id)
                }
            } catch {
                await MainActor.run {
                    generatingRelated = false
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Thử lại nhé."
                    relatedAlert = DuoAlertData(title: "Không tạo được bài học", message: msg)
                }
            }
        }
    }
}

// MARK: - Loading overlay (shared)

/// Friendly full-screen loading shown while the AI builds a lesson. Cycles
/// through reassuring status lines so the wait feels like part of the lesson.
struct GrammarLoadingOverlay: View {
    var pattern: String
    @State private var step = 0
    @State private var mascot = AnimatedGIF.randomWaiting()

    private let lines = [
        "Đang soạn bài học…",
        "Tìm ví dụ thực tế…",
        "Tạo phần luyện tập…",
        "Sắp xong rồi…"
    ]
    private let timer = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).opacity(0.96).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                AnimatedGIF(name: mascot).frame(width: 160, height: 160)
                if !pattern.isEmpty {
                    Text("“\(pattern)”").font(.title3.weight(.heavy)).foregroundStyle(.brand)
                        .multilineTextAlignment(.center)
                }
                Text(lines[step % lines.count])
                    .font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                    .contentTransition(.opacity)
                ProgressView().controlSize(.large).tint(.brand)
            }
            .padding(Theme.Spacing.lg)
        }
        .onReceive(timer) { _ in withAnimation { step += 1 } }
    }
}

// MARK: - 30-second summary card (shared with practice end)

struct GrammarSummaryCard: View {
    let pattern: String
    let summary: GrammarSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.duoGreen))
                Text("Tóm tắt 30 giây").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
            }
            row("Ý nghĩa", summary.meaning, icon: "text.bubble.fill", tint: .duoBlue)
            row("Cấu trúc", summary.structure, icon: "square.stack.3d.up.fill", tint: .duoIndigo)
            row("Mẹo nhớ", summary.keyTip, icon: "lightbulb.fill", tint: .duoGold)
            row("Tránh lỗi", summary.commonMistake, icon: "exclamationmark.triangle.fill", tint: .duoRed)
            if !summary.phrases.isEmpty {
                Text("CỤM CẦN NHỚ").font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                FlowLayout(spacing: 8) {
                    ForEach(Array(summary.phrases.enumerated()), id: \.offset) { _, p in
                        Text(p).font(.subheadline.weight(.bold)).foregroundStyle(.duoGreen)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.duoGreen.opacity(0.14)))
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    @ViewBuilder
    private func row(_ title: String, _ body: String, icon: String, tint: Color) -> some View {
        if !body.isEmpty {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption2.weight(.heavy)).foregroundStyle(.duoWolf)
                    Text(body).font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Lesson feedback sheet

/// A short Duolingo-style form for reporting a poor lesson. The chosen reasons
/// can be fed straight back into a regeneration to fix the specific complaint.
struct GrammarFeedbackSheet: View {
    let pattern: String
    /// (reasons, freeform note, alsoRegenerate)
    let onSubmit: (_ reasons: [String], _ note: String, _ regenerate: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var note = ""

    static let reasons = ["Ngữ pháp sai", "Ví dụ không tự nhiên", "Khó hiểu",
                          "Thiếu ví dụ", "Dịch chưa đúng", "Khác"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "flag.fill").font(.title2).foregroundStyle(.duoRed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Báo lỗi bài học").font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                        Text(pattern).font(.caption.weight(.bold)).foregroundStyle(.duoWolf).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text("BÀI HỌC CHƯA ỔN Ở ĐÂU?").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                FlowLayout(spacing: 8) {
                    ForEach(Self.reasons, id: \.self) { r in
                        let on = selected.contains(r)
                        Button {
                            Haptics.tap()
                            if on { selected.remove(r) } else { selected.insert(r) }
                        } label: {
                            Text(r)
                                .font(.subheadline.weight(.bold)).foregroundStyle(on ? .white : .duoInk)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(on ? AnyShapeStyle(Color.duoRed) : AnyShapeStyle(Color.duoPolar)))
                                .overlay(Capsule().strokeBorder(on ? Color.duoRedEdge : Color.duoSwan, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Mô tả thêm (tuỳ chọn)…", text: $note, axis: .vertical)
                    .lineLimit(1...4).font(.callout).foregroundStyle(.duoInk)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))

                Button {
                    onSubmit(Array(selected), note.trimmingCharacters(in: .whitespaces), true)
                    dismiss()
                } label: {
                    Label("Gửi & tạo lại bài học", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.duoPrimary(enabled: true))
                .padding(.top, Theme.Spacing.xs)

                Button {
                    onSubmit(Array(selected), note.trimmingCharacters(in: .whitespaces), false)
                    dismiss()
                } label: {
                    Text("Chỉ gửi phản hồi")
                        .font(.subheadline.weight(.heavy)).foregroundStyle(.duoWolf)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.lg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Practice setup (choose a context + exercise types, generate)

/// Carries a chosen exercise set into `navigationDestination` for the runner.
struct GrammarPracticeRun: Identifiable, Hashable {
    var id = UUID()
    var exercises: [GrammarExercise]
    /// The saved-set id (so the runner can record a score against it).
    var setID: UUID? = nil
    /// The chosen context label, stored on any mistakes recorded during the run.
    var contextLabel: String = "Bài học"
}

/// Shown before practice: pick a real-life CONTEXT (incl. IT), pick which
/// EXERCISE TYPES to drill, and let AI build a fresh set — or re-run a set you
/// generated before (saved on the lesson). Keeps practice varied and reusable.
struct GrammarPracticeSetupSheet: View {
    let pattern: String
    let request: String
    let defaultExercises: [GrammarExercise]
    @Bindable var store: GrammarStore
    let savedID: UUID?
    /// (exercises, contextLabel, savedSetID?)
    let onStart: ([GrammarExercise], String, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0
    @State private var custom = ""
    @State private var selectedTypes: Set<String> = Set(GrammarExercise.Kind.allCases.map(\.rawValue))
    @State private var generating = false
    @State private var alert: DuoAlertData?

    private struct Ctx { let label: String; let icon: String; let color: Color; let prompt: String? }
    private let contexts: [Ctx] = [
        .init(label: "Bài học", icon: "book.fill", color: .duoIndigo, prompt: nil),
        .init(label: "IT / Lập trình", icon: "chevron.left.forwardslash.chevron.right", color: .duoGreen,
              prompt: "lập trình & công nghệ thông tin (standup, code review, deploy, fix bug, sprint, họp kỹ thuật)"),
        .init(label: "Công việc", icon: "briefcase.fill", color: .duoBlue, prompt: "công việc văn phòng nói chung"),
        .init(label: "Du lịch", icon: "airplane", color: .duoGold, prompt: "du lịch"),
        .init(label: "Đời sống", icon: "house.fill", color: .duoGold, prompt: "đời sống hằng ngày"),
        .init(label: "IELTS", icon: "graduationcap.fill", color: .duoIndigo, prompt: "luyện thi IELTS học thuật"),
        .init(label: "Chủ đề khác", icon: "pencil", color: .duoWolf, prompt: "")
    ]
    private var isCustom: Bool { contexts[selected].prompt == "" }
    private var usesDefault: Bool { contexts[selected].prompt == nil }
    private var savedSets: [SavedExerciseSet] { savedID.flatMap { store.saved(id: $0) }?.exerciseSets ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header

                Text("CHỌN CHỦ ĐỀ BÀI TẬP").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    ForEach(contexts.indices, id: \.self) { i in contextChip(i) }
                }
                if isCustom {
                    TextField("VD: nhà hàng, phỏng vấn, thể thao…", text: $custom)
                        .font(.callout).padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.duoPolar))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.duoSwan, lineWidth: 2))
                }

                typeSection

                Text(usesDefault
                     ? "Dùng bài tập có sẵn trong bài học (lọc theo kiểu bạn chọn)."
                     : "AI sẽ tạo bộ bài tập mới theo chủ đề + kiểu bạn chọn, và lưu lại để luyện lần sau.")
                    .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)

                Button(action: start) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if generating { ProgressView().tint(.white); Text("Đang tạo bài tập…") }
                        else { Image(systemName: "play.fill"); Text("Bắt đầu luyện tập") }
                    }
                }
                .buttonStyle(.duoPrimary(enabled: canStart && !generating))
                .disabled(!canStart || generating)
                .padding(.top, Theme.Spacing.xs)

                if !savedSets.isEmpty { savedSetsSection }
            }
            .padding(Theme.Spacing.lg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .duoAlert($alert)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("Luyện tập").font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
                Text(pattern).font(.caption.weight(.bold)).foregroundStyle(.duoWolf).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func contextChip(_ i: Int) -> some View {
        let c = contexts[i]
        let on = selected == i
        return Button { Haptics.tap(); selected = i } label: {
            HStack(spacing: 8) {
                Image(systemName: c.icon).font(.subheadline.weight(.bold))
                Text(c.label).font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? .white : .duoInk)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? AnyShapeStyle(c.color) : AnyShapeStyle(Color.duoPolar)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(on ? c.color : Color.duoSwan, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Exercise-type picker

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("KIỂU BÀI TẬP").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                Spacer()
                Button(allTypesOn ? "Bỏ chọn hết" : "Chọn tất cả") {
                    if allTypesOn { selectedTypes.removeAll() }
                    else { selectedTypes = Set(GrammarExercise.Kind.allCases.map(\.rawValue)) }
                }
                .font(.caption.weight(.heavy)).foregroundStyle(.brand).buttonStyle(.plain)
            }
            FlowLayout(spacing: 8) {
                ForEach(GrammarExercise.Kind.allCases) { kind in typeChip(kind) }
            }
        }
    }

    private var allTypesOn: Bool { selectedTypes.count == GrammarExercise.Kind.allCases.count }

    private func typeChip(_ kind: GrammarExercise.Kind) -> some View {
        let on = selectedTypes.contains(kind.rawValue)
        return Button {
            Haptics.tap()
            if on { selectedTypes.remove(kind.rawValue) } else { selectedTypes.insert(kind.rawValue) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.icon).font(.caption2.weight(.bold))
                Text(kind.label).font(.caption.weight(.heavy))
            }
            .foregroundStyle(on ? .white : .duoInk)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Capsule().fill(on ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.duoPolar)))
            .overlay(Capsule().strokeBorder(on ? Color.brandEdge : Color.duoSwan, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Saved sets

    private var savedSetsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("BỘ BÀI TẬP ĐÃ LƯU").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                .padding(.top, Theme.Spacing.sm)
            ForEach(savedSets) { set in
                Button {
                    onStart(set.exercises, set.contextLabel, set.id); dismiss()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "tray.full.fill").foregroundStyle(.duoIndigo)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.duoIndigo.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.contextLabel).font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk)
                            Text("\(set.exercises.count) câu · \(set.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2.weight(.bold)).foregroundStyle(.duoWolf)
                        }
                        Spacer(minLength: 0)
                        if let s = set.bestScore {
                            Text("\(s)đ").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(scoreColor(s)))
                        }
                        Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.brand)
                    }
                    .padding(Theme.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let id = savedID {
                        Button(role: .destructive) {
                            store.deleteExerciseSet(setID: set.id, fromSaved: id)
                        } label: { Label("Xóa", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func scoreColor(_ s: Int) -> Color { s >= 85 ? .duoGreen : (s >= 60 ? .duoGold : .duoRed) }

    // MARK: Start

    private var canStart: Bool {
        if usesDefault { return !defaultExercises.isEmpty }
        if isCustom { return !custom.trimmingCharacters(in: .whitespaces).isEmpty && AppConfiguration.hasGeminiKey }
        return AppConfiguration.hasGeminiKey
    }

    /// The chosen types, or `[]` (= any) when all are selected.
    private var chosenTypes: [String] {
        allTypesOn ? [] : Array(selectedTypes)
    }

    private func start() {
        let c = contexts[selected]
        guard let promptCtx = c.prompt else {
            onStart(filteredDefault(), "Bài học", nil); dismiss(); return
        }
        let ctx = isCustom ? custom.trimmingCharacters(in: .whitespaces) : promptCtx
        generating = true
        Task {
            do {
                let ex = try await GrammarAIService().generateExercises(
                    pattern: pattern, context: ctx, types: chosenTypes, count: 8)
                await MainActor.run {
                    generating = false
                    // Save the generated set on the lesson so it can be re-run.
                    var setID: UUID? = nil
                    if let id = savedID {
                        setID = store.addExerciseSet(SavedExerciseSet(contextLabel: c.label, exercises: ex), toSaved: id)
                    }
                    onStart(ex, c.label, setID)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    generating = false
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Thử lại nhé."
                    alert = DuoAlertData(title: "Không tạo được bài tập", message: msg)
                }
            }
        }
    }

    /// The lesson's own exercises limited to the chosen types (falls back to all).
    private func filteredDefault() -> [GrammarExercise] {
        guard !chosenTypes.isEmpty else { return defaultExercises }
        let set = Set(chosenTypes)
        let filtered = defaultExercises.filter { set.contains($0.type) }
        return filtered.isEmpty ? defaultExercises : filtered
    }
}
