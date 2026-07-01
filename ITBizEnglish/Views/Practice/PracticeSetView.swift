//
//  PracticeSetView.swift
//  ITBizEnglish
//
//  A set of Vietnamese sentences to practice writing in English. Add sentences
//  (optionally let AI suggest a reference answer), then tap one to write + get
//  graded by AI.
//

import SwiftUI

struct PracticeSetView: View {
    @Bindable var store: PracticeStore
    let setID: UUID
    var decks: DeckStore

    @State private var showAdd = false
    @State private var showGenerate = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showIconPicker = false
    @State private var showListening = false
    @State private var showNewSessionConfirm = false
    @State private var currentSentenceID: UUID?
    /// Ordered IDs the active practice run walks through. Empty = the whole set;
    /// set to the flagged IDs when reviewing difficult sentences on their own.
    @State private var practiceQueue: [UUID] = []

    private var set: PracticeSet? { store.set(id: setID) }

    /// Where "Start / Continue practice" begins: the first un-practiced
    /// sentence, or the first sentence if everything's been checked.
    private func firstSentenceID(in set: PracticeSet) -> UUID? {
        set.sentences.first { !$0.hasBeenChecked }?.id ?? set.sentences.first?.id
    }

    // MARK: - Session complete

    /// Shown once every sentence has been checked: celebrate, show the average
    /// score, and offer to archive this session and start a fresh one.
    private func completionCard(_ set: PracticeSet) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            AnimatedGIF(name: "happy").frame(width: 96, height: 96)
            Text("Hoàn thành Session \(set.session)! 🎉")
                .font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
            HStack(spacing: 6) {
                Text("Điểm trung bình").font(.subheadline.weight(.bold)).foregroundStyle(.duoWolf)
                Text("\(set.currentAverage)")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(scoreColor(set.currentAverage))
            }
            Button { showNewSessionConfirm = true } label: {
                Label("Bắt đầu session mới", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.brand)
            Text("Kết quả session này sẽ được lưu vào Lịch sử để bạn so sánh.")
                .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Color.brand.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Color.brand.opacity(0.5), lineWidth: 2))
    }

    private func scoreColor(_ s: Int) -> Color { s >= 85 ? .duoGreen : (s >= 60 ? .duoGold : .duoRed) }

    // MARK: - Duolingo-style sentence list

    private func sentenceList(_ set: PracticeSet) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Progress header card.
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Label("Session \(set.session)", systemImage: "flag.checkered")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(.duoIndigo)
                        Spacer()
                        Text("\(Int(set.progress * 100))%")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(.duoIndigo)
                    }
                    DuoProgressBar(value: set.progress, tint: .duoIndigo, height: 14)
                    HStack {
                        Text("\(set.checkedCount)/\(set.total) câu đã luyện")
                            .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                        Spacer()
                    }
                }
                .padding(Theme.Spacing.md)
                .duoCard(cornerRadius: Theme.Radius.card)

                if set.isComplete {
                    completionCard(set)
                } else {
                    // Start / Continue button.
                    Button {
                        withAnimation {
                            practiceQueue = []          // walk the whole set
                            currentSentenceID = firstSentenceID(in: set)
                        }
                    } label: {
                        Label(set.checkedCount == 0 ? "Bắt đầu luyện" : "Luyện tiếp", systemImage: "play.fill")
                    }
                    .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge))
                }

                // Review only the flagged "hard" sentences, on their own.
                if set.difficultCount > 0 {
                    Button {
                        let ids = set.difficultSentences.map(\.id)
                        withAnimation {
                            practiceQueue = ids
                            currentSentenceID = ids.first
                        }
                    } label: {
                        Label("Ôn câu khó (\(set.difficultCount))", systemImage: "flag.fill")
                    }
                    .buttonStyle(.duo(.duoRed, edge: .duoRedEdge))
                }

                // Listening practice (arrange words from the audio).
                let canListen = set.sentences.contains {
                    !$0.referenceEnglish.trimmingCharacters(in: .whitespaces).isEmpty
                }
                Button { showListening = true } label: {
                    Label("Luyện nghe", systemImage: "headphones")
                }
                .buttonStyle(.duo(.duoBlue, edge: .duoBlueEdge, enabled: canListen))
                .disabled(!canListen)

                // History of past sessions (only once something is archived).
                if set.hasHistory {
                    NavigationLink {
                        PracticeHistoryView(store: store, setID: setID)
                    } label: {
                        Label("Lịch sử các lần dịch", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.duo(.duoGold, edge: .duoGoldEdge))
                }

                HStack {
                    Text("CÂU").font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
                    Spacer()
                }
                .padding(.top, Theme.Spacing.xs)

                ForEach(set.sentences) { s in
                    Button {
                        practiceQueue = []          // tapping a row walks the whole set
                        currentSentenceID = s.id
                    } label: {
                        SentenceRow(sentence: s)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            store.toggleDifficult(forSentence: s.id, inSet: setID)
                        } label: {
                            Label(s.isDifficult ? "Bỏ đánh dấu khó" : "Đánh dấu câu khó",
                                  systemImage: s.isDifficult ? "flag.slash" : "flag")
                        }
                        Button(role: .destructive) {
                            withAnimation { store.deleteSentence(s.id, fromSet: setID) }
                        } label: { Label("Xóa", systemImage: "trash") }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            if let set {
                if set.sentences.isEmpty {
                    VStack(spacing: Theme.Spacing.lg) {
                        AnimatedGIF(name: "waiting3").frame(width: 150, height: 150)
                        VStack(spacing: 6) {
                            Text("Chưa có câu nào").font(.title2.weight(.heavy)).foregroundStyle(.duoInk)
                            Text("Thêm câu tiếng Việt bạn muốn nói được bằng tiếng Anh.")
                                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                                .multilineTextAlignment(.center)
                        }
                        VStack(spacing: Theme.Spacing.sm) {
                            Button("Thêm câu") { showAdd = true }
                                .buttonStyle(.duo(.duoIndigo, edge: .duoIndigoEdge))
                            Button { showGenerate = true } label: {
                                Label("Tạo bằng AI", systemImage: "sparkles")
                            }
                            .font(.subheadline.weight(.heavy)).tint(.duoIndigo)
                        }
                        .frame(maxWidth: 280)
                    }
                    .padding(Theme.Spacing.lg)
                } else {
                    if let currentSentenceID, set.sentences.contains(where: { $0.id == currentSentenceID }) {
                        PracticeWriteView(store: store, setID: setID, sentenceID: currentSentenceID, decks: decks, queue: practiceQueue, onNext: { nextID in
                            withAnimation {
                                self.currentSentenceID = nextID
                                if nextID == nil { practiceQueue = [] }
                            }
                        })
                        .id(currentSentenceID)   // fresh state per sentence
                    } else {
                        sentenceList(set)
                    }
                }
            } else {
                ContentUnavailableView("Set not found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(set?.title ?? "Set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAdd = true } label: { Label("Add sentence", systemImage: "plus") }
                    Button { showGenerate = true } label: { Label("Generate with AI", systemImage: "sparkles") }
                    Button {
                        renameText = set?.title ?? ""; showRename = true
                    } label: { Label("Đổi tên", systemImage: "pencil") }
                    Button { showIconPicker = true } label: {
                        Label("Đổi icon & màu", systemImage: "paintbrush.fill")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddSentenceView(store: store, setID: setID)
        }
        .sheet(isPresented: $showGenerate) {
            GenerateSentencesView(store: store, setID: setID, defaultTopic: set?.title ?? "")
        }
        .sheet(isPresented: $showIconPicker) {
            IconColorPicker(icon: set?.icon ?? "pencil.and.scribble",
                            colorHex: set?.colorHex ?? 0xA560E8) { icon, color in
                store.setAppearance(icon: icon, colorHex: color, forSet: setID)
            }
        }
        .fullScreenCover(isPresented: $showListening) {
            ListeningSessionView(store: store, setID: setID)
        }
        .alert("Rename set", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.renameSet(id: setID, to: t) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Bắt đầu session mới?", isPresented: $showNewSessionConfirm) {
            Button("Bắt đầu") {
                withAnimation {
                    store.startNewSession(forSet: setID)
                    currentSentenceID = nil
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Kết quả session hiện tại sẽ được lưu vào Lịch sử, rồi bạn luyện lại từ đầu.")
        }
    }
}


private struct SentenceRow: View {
    let sentence: PracticeSentence
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Status dot / score badge.
            if let fb = sentence.feedback {
                Text("\(fb.score)")
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(fb.ratingColor))
            } else {
                Image(systemName: "circle.dashed")
                    .font(.title3.weight(.bold)).foregroundStyle(.duoSwan)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if sentence.isDifficult {
                        Image(systemName: "flag.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(.duoRed)
                    }
                    Text(sentence.vietnamese)
                        .font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk).lineLimit(2)
                }
                if !sentence.referenceEnglish.isEmpty {
                    Text(sentence.referenceEnglish)
                        .font(.caption.weight(.medium)).foregroundStyle(.duoWolf).lineLimit(1)
                } else {
                    Text("Chưa luyện").font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.duoSwan)
        }
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

// MARK: - Add sentence (with optional AI suggested reference)

private struct AddSentenceView: View {
    @Bindable var store: PracticeStore
    let setID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var vietnamese = ""
    @State private var reference = ""
    @State private var isSuggesting = false
    @State private var error: String?

    private var canAdd: Bool { !vietnamese.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        fieldCard(title: "CÂU TIẾNG VIỆT") {
                            TextField("Câu bạn muốn nói được…", text: $vietnamese, axis: .vertical)
                                .lineLimit(2...5).font(.body.weight(.medium)).foregroundStyle(.duoInk)
                        }

                        fieldCard(title: "BẢN DỊCH THAM KHẢO (TUỲ CHỌN)") {
                            TextField("Tiếng Anh…", text: $reference, axis: .vertical)
                                .lineLimit(1...4).font(.body.weight(.medium)).foregroundStyle(.duoInk)
                            Divider()
                            Button { suggest() } label: {
                                HStack(spacing: 6) {
                                    if isSuggesting { ProgressView().controlSize(.small) }
                                    Label("Gợi ý bằng AI", systemImage: "sparkles")
                                        .font(.subheadline.weight(.heavy))
                                }
                                .foregroundStyle(.duoIndigo)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSuggesting || !canAdd || !AppConfiguration.hasGeminiKey)
                        }

                        Text(AppConfiguration.hasGeminiKey
                             ? "Bản dịch chỉ là gợi ý — AI chấm theo cách diễn đạt của bạn."
                             : "⚠️ Thêm Gemini key trong Cài đặt để dùng gợi ý AI.")
                            .font(.caption.weight(.medium)).foregroundStyle(.duoWolf)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout.weight(.bold)).foregroundStyle(.duoRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button("Thêm câu", action: add)
                            .buttonStyle(.duoPrimary(enabled: canAdd))
                            .disabled(!canAdd)
                            .keyboardShortcut(.return, modifiers: .command)   // ⌘+Return adds
                            .padding(.top, Theme.Spacing.sm)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Thêm câu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func fieldCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(.duoWolf)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func add() {
        let s = PracticeSentence(
            vietnamese: vietnamese.trimmingCharacters(in: .whitespacesAndNewlines),
            referenceEnglish: reference.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addSentence(s, toSet: setID)
        dismiss()
    }

    private func suggest() {
        error = nil
        isSuggesting = true
        Task {
            do {
                let result = try await GeminiTranslationService().translate(vietnamese)
                await MainActor.run {
                    reference = result.englishOptions.professional
                    isSuggesting = false
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isSuggesting = false
                }
            }
        }
    }
}

// MARK: - Listening practice (hear the sentence, arrange the words)

struct ListeningSessionView: View {
    @Bindable var store: PracticeStore
    let setID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechSynthesizer()

    private struct Tile: Identifiable, Equatable { let id = UUID(); let text: String }

    @State private var queue: [PracticeSentence] = []
    @State private var index = 0
    @State private var bank: [Tile] = []
    @State private var chosen: [Tile] = []
    @State private var result: Bool? = nil
    @State private var mascot = AnimatedGIF.randomWaiting()
    @State private var finished = false
    @State private var audioProgress: CGFloat = 0     // 0...1 fills as audio plays
    @State private var bumpedIDs: Set<UUID> = []       // staggered pop on correct

    private var current: PracticeSentence? { index < queue.count ? queue[index] : nil }
    private var progress: Double { queue.isEmpty ? 0 : Double(index) / Double(queue.count) }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
            if finished || queue.isEmpty {
                finishView
            } else if let s = current {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    ScrollView {
                        content(s).padding(.horizontal, Theme.Spacing.md).padding(.bottom, 220)
                    }
                }
                .padding(.top, Theme.Spacing.sm)
                bottomBar(s)
            }
        }
        .onAppear(perform: start)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundStyle(.duoHare)
            }
            DuoProgressBar(value: progress)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Content

    private func content(_ s: PracticeSentence) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Nghe và điền")
                .font(.title2.weight(.heavy)).foregroundStyle(.duoInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                AnimatedGIF(name: mascot).frame(width: 124, height: 144)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button { play(s, slow: false) } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.title2).foregroundStyle(.duoBlue)
                        }.buttonStyle(.plain)
                        waveform
                    }
                    .padding(.horizontal, Theme.Spacing.md).padding(.vertical, 12)
                    .duoCard(cornerRadius: 18)

                    Button { play(s, slow: true) } label: {
                        Text("CHẬM").font(.caption.weight(.heavy)).foregroundStyle(.duoBlue)
                    }.buttonStyle(.plain)
                }
            }

            // Answer area: chosen tiles sit directly on a writing line.
            VStack(spacing: 0) {
                FlowLayout(spacing: 8) {
                    ForEach(chosen) { tile in tileView(tile, inChosen: true) }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .bottomLeading)
                Rectangle().fill(Color.duoSwan).frame(height: 2)
                Spacer().frame(height: 44)
                Rectangle().fill(Color.duoSwan).frame(height: 2)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let str = items.first, let id = UUID(uuidString: str) else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { moveToChosen(id: id, before: nil) }
                return true
            }

            // Word bank.
            FlowLayout(spacing: 8) {
                ForEach(bank) { tile in tileView(tile, inChosen: false) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let str = items.first, let id = UUID(uuidString: str) else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { moveToBank(id: id) }
                return true
            }
        }
    }

    /// Bars fill blue up to the current audio progress.
    private var waveform: some View {
        let heights: [CGFloat] = [8,14,20,26,18,30,22,28,16,24,12,18,10,22,14]
        return HStack(spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                let on = CGFloat(i) / CGFloat(heights.count) <= audioProgress
                Capsule().fill(on ? Color.duoBlue : Color.duoSwan)
                    .frame(width: 3, height: h)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tileView(_ tile: Tile, inChosen: Bool) -> some View {
        let correct = result == true && inChosen
        let chip = Button {
            guard result == nil else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if inChosen { moveToBank(id: tile.id) } else { moveToChosen(id: tile.id, before: nil) }
            }
        } label: {
            Text(tile.text)
                .font(.body.weight(.bold)).foregroundStyle(correct ? .duoOkText : .duoInk)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(correct ? Color.duoOkFill : Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(correct ? Color.duoOkBorder : Color.duoSwan, lineWidth: 2))
                .correctCelebration(trigger: bumpedIDs.contains(tile.id), cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .draggable(tile.id.uuidString)

        if inChosen {
            chip.dropDestination(for: String.self) { items, _ in
                guard let str = items.first, let id = UUID(uuidString: str) else { return false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { moveToChosen(id: id, before: tile.id) }
                return true
            }
        } else {
            chip
        }
    }

    // MARK: - Tile moves (tap + drag)

    private func removeTile(id: UUID) -> Tile? {
        if let i = chosen.firstIndex(where: { $0.id == id }) { return chosen.remove(at: i) }
        if let i = bank.firstIndex(where: { $0.id == id }) { return bank.remove(at: i) }
        return nil
    }
    private func moveToChosen(id: UUID, before targetID: UUID?) {
        guard result == nil, id != targetID, let tile = removeTile(id: id) else { return }
        if let targetID, let idx = chosen.firstIndex(where: { $0.id == targetID }) {
            chosen.insert(tile, at: idx)
        } else { chosen.append(tile) }
    }
    private func moveToBank(id: UUID) {
        guard result == nil, let i = chosen.firstIndex(where: { $0.id == id }) else { return }
        bank.append(chosen.remove(at: i))
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private func bottomBar(_ s: PracticeSentence) -> some View {
        if let ok = result {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label(ok ? "Xuất sắc!" : "Đáp án đúng:",
                      systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3.weight(.heavy)).foregroundStyle(ok ? .brand : .duoWrongText)
                    .symbolEffect(.bounce, value: ok)
                if !ok {
                    Text(s.referenceEnglish).font(.body.weight(.bold)).foregroundStyle(.duoInk)
                }
                Text("Nghĩa là:").font(.subheadline.weight(.heavy)).foregroundStyle(ok ? .brand : .duoWolf)
                Text(s.vietnamese).font(.subheadline.weight(.medium)).foregroundStyle(ok ? .brand : .duoInk)
                Button("Tiếp tục", action: advance)
                    .buttonStyle(ok ? .brand : .duoRed)
                    .padding(.top, 4)
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack { Color(.systemBackground); (ok ? Color.brand.opacity(0.15) : Color.duoWrongFill) }
                    .ignoresSafeArea(edges: .bottom)
            )
        } else {
            Button("Kiểm tra") { check(s) }
                .buttonStyle(.duoPrimary(enabled: !chosen.isEmpty))
                .disabled(chosen.isEmpty)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
        }
    }

    private var finishView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AnimatedGIF(name: "happy").frame(width: 200, height: 200)
            Text("Hoàn thành luyện nghe!").font(.title.weight(.heavy)).foregroundStyle(.duoInk)
            Button("Xong") { dismiss() }
                .buttonStyle(.brand).padding(.horizontal, Theme.Spacing.lg)
        }
        .padding()
        .onAppear { SoundFX.completed() }
    }

    // MARK: - Logic

    private func start() {
        guard queue.isEmpty, let set = store.set(id: setID) else { return }
        queue = set.sentences.filter { !$0.referenceEnglish.trimmingCharacters(in: .whitespaces).isEmpty }.shuffled()
        loadCurrent()
    }

    private func loadCurrent() {
        guard let s = current else { finished = true; return }
        let target = s.referenceEnglish.split(separator: " ").map(String.init)
        var pool = Set<String>()
        for other in queue where other.id != s.id {
            for w in other.referenceEnglish.split(separator: " ") { pool.insert(String(w)) }
        }
        let distractors = Array(pool.subtracting(target).shuffled().prefix(3))
        withAnimation {
            bank = (target + distractors).shuffled().map { Tile(text: $0) }
            chosen = []
            result = nil
        }
        bumpedIDs = []
        audioProgress = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { play(s, slow: false) }
    }

    private func play(_ s: PracticeSentence, slow: Bool) {
        speech.stop()
        speech.speak(s.referenceEnglish, id: "listen-\(s.id)-\(slow)", rate: slow ? 0.32 : 0.46)
        // Run the waveform fill over the (estimated) clip length.
        let est = max(0.6, Double(s.referenceEnglish.count) * (slow ? 0.115 : 0.075))
        audioProgress = 0
        withAnimation(.linear(duration: est)) { audioProgress = 1 }
    }

    private func check(_ s: PracticeSentence) {
        let attempt = chosen.map(\.text).joined(separator: " ")
        func norm(_ x: String) -> String { x.lowercased().split(separator: " ").joined(separator: " ") }
        let ok = norm(attempt) == norm(s.referenceEnglish)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { result = ok }
        if ok { SoundFX.correct(); celebratePop() } else { SoundFX.wrong() }
    }

    /// Raises the chosen tiles one by one when the answer is correct.
    private func celebratePop() {
        for (i, tile) in chosen.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                bumpedIDs.insert(tile.id)
            }
        }
    }

    private func advance() {
        withAnimation { index += 1 }
        loadCurrent()
    }
}
