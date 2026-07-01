//
//  DeckGameView.swift
//  ITBizEnglish
//
//  A fast, fun review game over a course's words: hear/see the English word,
//  beat the timer to pick the right Vietnamese meaning. Build combos for bonus
//  points, but you only have 3 hearts. Wrong picks reveal the word and bring it
//  back later so you get another shot.
//

import SwiftUI

struct DeckGameView: View {
    @Bindable var store: DeckStore
    let deckID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechSynthesizer()

    private struct Question: Identifiable, Equatable {
        let id = UUID()
        let word: DeckWord
        let options: [String]   // Vietnamese meanings, shuffled
    }

    @State private var queue: [Question] = []
    @State private var score = 0
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var hearts = 3
    @State private var answered = 0
    @State private var timeLeft = 1.0
    @State private var picked: String?
    @State private var locked = false
    @State private var lastCorrect = false
    @State private var finished = false
    @State private var didWin = false

    // Liveliness state
    private enum Reaction { case idle, happy, angry }
    @State private var reaction: Reaction = .idle
    @State private var idleMascot = AnimatedGIF.randomWaiting()
    @State private var lastGain = 0          // points from the last correct answer
    @State private var superFast = false     // answered very quickly
    @State private var comboBanner: String?  // "COMBO x3!"
    @State private var flash = false         // red screen flash on a miss
    @State private var appeared = false      // drives the staggered option entrance
    @State private var lowTickSecond = -1    // last whole second a tension haptic fired

    private let questionTime = 7.0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var current: Question? { queue.first }

    var body: some View {
        ZStack {
            AppBackground()
            if store.deck(id: deckID).map({ $0.learnedWords.count < 4 }) ?? true {
                notEnough
            } else if finished {
                results
            } else if let q = current {
                game(q)
            } else {
                Color.clear.onAppear(perform: build)
            }
        }
        .onAppear(perform: build)
        .onReceive(timer) { _ in tick() }
    }

    // MARK: - Game

    private func game(_ q: Question) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar
            timeBar.opacity(timeBarOpacity)

            Spacer(minLength: 0)

            // Reacting mascot + the word to translate.
            AnimatedGIF(name: reactionGif)
                .frame(width: 96, height: 96)
                .scaleEffect(reaction == .idle ? 1 : 1.08)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: reaction)

            VStack(spacing: 8) {
                Text("Từ này nghĩa là gì?").font(.subheadline.weight(.bold)).foregroundStyle(.duoWolf)
                HStack(spacing: Theme.Spacing.sm) {
                    Text(q.word.word).font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.duoInk)
                    Button { speech.speak(q.word.word, id: q.id.uuidString) } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.title3).foregroundStyle(.duoBlue)
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(q.options.enumerated()), id: \.element) { index, option in
                    DuoChoiceCard(state: choiceState(option, q)) {
                        choose(option, in: q)
                    } content: {
                        Text(option)
                    }
                    .disabled(locked)
                    // Hardware keyboard: press 1–4 to pick that option.
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    .scaleEffect(choiceState(option, q) == .correct ? 1.05 : 1)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.07), value: appeared)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: locked)
                }
            }

            if locked && !lastCorrect { WrongRevealCard(word: q.word) }
        }
        .padding(Theme.Spacing.md)
        // Combo glow intensifies the higher your streak.
        .background(Color.duoGold.opacity(min(0.22, Double(combo) * 0.035)).ignoresSafeArea())
        // Red flash on a miss.
        .overlay(Color.duoRed.opacity(flash ? 0.22 : 0).ignoresSafeArea().allowsHitTesting(false))
        .animation(.easeOut(duration: 0.3), value: flash)
        // Big combo banner.
        .overlay(alignment: .top) {
            if let comboBanner {
                Text(comboBanner)
                    .font(.title.weight(.black)).foregroundStyle(.duoGold)
                    .shadow(color: .duoGoldEdge.opacity(0.5), radius: 1, y: 1)
                    .padding(.top, 70)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .id(q.id)
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                removal: .opacity))
        .onAppear {
            appeared = false
            DispatchQueue.main.async { appeared = true }
        }
    }

    private var reactionGif: String {
        switch reaction {
        case .idle:  return idleMascot
        case .happy: return "happy"
        case .angry: return "angry"
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline.weight(.bold)).foregroundStyle(.duoWolf) }
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < hearts ? "heart.fill" : "heart")
                        .foregroundStyle(.duoRed).font(.subheadline)
                }
            }
            .symbolEffect(.bounce, value: hearts)
            Spacer()
            if combo >= 2 {
                Label("\(combo)x", systemImage: "flame.fill")
                    .font(.subheadline.weight(.heavy)).foregroundStyle(.duoGold)
                    .symbolEffect(.bounce, value: combo)
                    .transition(.scale)
            }
            Text("\(score)").font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(.duoInk).frame(minWidth: 44, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.snappy, value: score)
        }
        // Floating "+points" / "SIÊU NHANH!" on a correct answer.
        .overlay(alignment: .trailing) {
            if locked && lastCorrect {
                Text(superFast ? "+\(lastGain) ⚡" : "+\(lastGain)")
                    .font(.headline.weight(.black)).foregroundStyle(.brand)
                    .offset(y: -26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var timeBar: some View {
        DuoProgressBar(value: max(0, timeLeft / questionTime),
                       tint: timeLeft / questionTime < 0.3 ? .duoRed : .duoBlue,
                       height: 12)
    }

    /// Blinks the timer bar when time is running out.
    private var timeBarOpacity: Double {
        let frac = timeLeft / questionTime
        guard frac < 0.4, !locked else { return 1 }
        return 0.55 + 0.45 * abs(sin(timeLeft * 10))
    }

    private func choiceState(_ o: String, _ q: Question) -> DuoChoiceState {
        guard locked else { return .normal }
        if o == q.word.meaning { return .correct }
        if o == picked { return .wrong }
        return .dimmed
    }

    // MARK: - Logic

    private func build() {
        guard queue.isEmpty, let deck = store.deck(id: deckID), deck.learnedWords.count >= 4 else { return }
        let chosen = Array(deck.learnedWords.shuffled().prefix(10))
        queue = chosen.map { word in
            var distractors = deck.words.filter { $0.id != word.id }.map(\.meaning).shuffled()
            var opts = Array(distractors.prefix(3))
            opts.append(word.meaning)
            distractors.removeAll()
            return Question(word: word, options: opts.shuffled())
        }
        timeLeft = questionTime
    }

    private func tick() {
        guard !finished, !locked, current != nil else { return }
        timeLeft -= 0.05
        // Tension haptic once per second when time is nearly up.
        if timeLeft / questionTime < 0.4 {
            let sec = Int(ceil(timeLeft))
            if sec != lowTickSecond { lowTickSecond = sec; Haptics.tap() }
        }
        if timeLeft <= 0 { resolve(correct: false, picked: nil) }
    }

    private func choose(_ option: String, in q: Question) {
        guard !locked else { return }
        resolve(correct: option == q.word.meaning, picked: option)
    }

    private func resolve(correct: Bool, picked: String?) {
        guard let q = current else { return }
        locked = true
        self.picked = picked
        lastCorrect = correct

        let frac = timeLeft / questionTime

        if correct {
            combo += 1
            bestCombo = max(bestCombo, combo)
            let speedBonus = Int(max(0, frac) * 10)        // answer fast → more points
            let gained = 10 + (combo - 1) * 5 + speedBonus
            withAnimation(.snappy) { score += gained }
            lastGain = gained
            superFast = frac > 0.65
            reaction = .happy
            if combo >= 2 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { comboBanner = "COMBO x\(combo)!" }
            }
            SoundFX.correct()
        } else {
            combo = 0
            hearts -= 1
            reaction = .angry
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { flash = false }
            SoundFX.wrong()
        }
        _ = q

        let delay = correct ? 0.8 : 1.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { advance(wasCorrect: correct) }
    }

    private func advance(wasCorrect: Bool) {
        guard !queue.isEmpty else { return }
        let q = queue.removeFirst()
        answered += 1
        if !wasCorrect { queue.append(q) }   // re-show missed words later

        picked = nil
        locked = false
        timeLeft = questionTime
        lowTickSecond = -1
        reaction = .idle
        comboBanner = nil

        if hearts <= 0 { didWin = false; finished = true }
        else if queue.isEmpty { didWin = true; finished = true }
    }

    // MARK: - States

    private var results: some View {
        VStack(spacing: Theme.Spacing.md) {
            AnimatedGIF(name: didWin ? "happy" : "angry")
                .frame(width: 200, height: 200)
            Text(didWin ? "Hoàn thành Speed Review!" : "Hết tim rồi!")
                .font(.title2.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Điểm \(score) · Combo cao nhất \(bestCombo)x")
                .font(.headline.weight(.bold)).foregroundStyle(.duoWolf)
            VStack(spacing: Theme.Spacing.sm) {
                Button("Chơi lại") { restart() }.buttonStyle(.duoGreen)
                    .keyboardShortcut(.defaultAction)   // Return → chơi lại
                Button("Xong") { dismiss() }
                    .buttonStyle(DuoButtonStyle(color: .duoPolar, edge: .duoSwan, foreground: .duoWolf))
            }
            .padding(.top)
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private func restart() {
        queue = []; score = 0; combo = 0; bestCombo = 0; hearts = 3
        answered = 0; picked = nil; locked = false; finished = false; didWin = false
        reaction = .idle; comboBanner = nil; flash = false; lowTickSecond = -1
        idleMascot = AnimatedGIF.randomWaiting()
        build()
    }

    private var notEnough: some View {
        ContentUnavailableView {
            Label("Chưa đủ từ đã học", systemImage: "bolt.slash")
        } description: {
            Text("Học ít nhất 4 từ trong khóa này (mỗi từ ≥ 1 lần) để chơi Speed Review.")
        } actions: {
            Button("Đóng") { dismiss() }
        }
    }
}

// MARK: - Wrong reveal

private struct WrongRevealCard: View {
    let word: DeckWord
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(word.word) — \(word.meaning)")
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoWrongText)
            if !word.example.isEmpty {
                Text("“\(word.example)”").font(.caption.weight(.medium).italic()).foregroundStyle(.duoWolf)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoWrongFill))
        .transition(.opacity)
    }
}

#Preview {
    DeckGameView(store: DeckStore(), deckID: WordDeck.sample.id)
}
