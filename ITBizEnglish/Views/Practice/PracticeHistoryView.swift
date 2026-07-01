//
//  PracticeHistoryView.swift
//  ITBizEnglish
//
//  Looks back over a Self-Translate set's past practice sessions so the user can
//  compare how their translations improve over time: a per-session score trend
//  at the top, then each archived session (newest first) expands to show every
//  sentence — the Vietnamese, what the user wrote, and the AI's grade + fixes.
//

import SwiftUI

struct PracticeHistoryView: View {
    @Bindable var store: PracticeStore
    let setID: UUID

    @State private var expanded: Set<Int> = []

    private var set: PracticeSet? { store.set(id: setID) }

    /// Past attempts grouped by the session they belonged to, newest first.
    private var sessions: [SessionGroup] {
        guard let set else { return [] }
        var bySession: [Int: [SessionGroup.Item]] = [:]
        for sentence in set.sentences {
            for attempt in sentence.history {
                bySession[attempt.session, default: []].append(
                    .init(id: attempt.id, vietnamese: sentence.vietnamese, attempt: attempt)
                )
            }
        }
        return bySession.map { session, items in
            SessionGroup(session: session,
                         date: items.map(\.attempt.date).max() ?? .now,
                         items: items.sorted { $0.attempt.date < $1.attempt.date })
        }
        .sorted { $0.session > $1.session }
    }

    var body: some View {
        ZStack {
            AppBackground()
            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        trendCard
                        ForEach(sessions) { sessionCard($0) }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .navigationTitle("Lịch sử")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let first = sessions.first?.session { expanded = [first] } }
    }

    // MARK: - Trend chart

    private var trendCard: some View {
        // Oldest → newest left-to-right so improvement reads naturally.
        let ordered = sessions.sorted { $0.session < $1.session }
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.duoIndigo))
                Text("Điểm theo session").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                ForEach(ordered) { s in
                    VStack(spacing: 6) {
                        Text("\(s.average)")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(scoreColor(s.average))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(scoreColor(s.average))
                            .frame(height: max(8, CGFloat(s.average) / 100 * 120))
                        Text("S\(s.session)")
                            .font(.caption2.weight(.bold)).foregroundStyle(.duoWolf)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ordered.count)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    // MARK: - Session card

    private func sessionCard(_ s: SessionGroup) -> some View {
        let isOpen = expanded.contains(s.session)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isOpen { expanded.remove(s.session) } else { expanded.insert(s.session) }
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    scoreBadge(s.average, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session \(s.session)").font(.headline.weight(.heavy)).foregroundStyle(.duoInk)
                        Text("\(s.items.count) câu · \(s.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.heavy)).foregroundStyle(.duoWolf)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .padding(Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(s.items) { item in attemptRow(item) }
                }
                .padding([.horizontal, .bottom], Theme.Spacing.md)
            }
        }
        .duoCard(cornerRadius: Theme.Radius.card)
    }

    private func attemptRow(_ item: SessionGroup.Item) -> some View {
        let fb = item.attempt.feedback
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.vietnamese)
                .font(.subheadline.weight(.heavy)).foregroundStyle(.duoInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            // What the user wrote.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "pencil").font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
                Text(item.attempt.attempt.isEmpty ? "—" : item.attempt.attempt)
                    .font(.callout.weight(.bold)).foregroundStyle(.duoInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let fb { scoreBadge(fb.score, size: 34) }
            }

            if let fb {
                if !fb.verdict.isEmpty {
                    Text("\(fb.emoji) \(fb.verdict)")
                        .font(.caption.weight(.heavy)).foregroundStyle(scoreColor(fb.score))
                }
                if !fb.correctedVersion.isEmpty,
                   normalized(fb.correctedVersion) != normalized(item.attempt.attempt) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.caption.weight(.bold)).foregroundStyle(.duoGreen)
                        Text(fb.correctedVersion)
                            .font(.callout.weight(.medium)).foregroundStyle(.duoOkText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("Chưa chấm").font(.caption.weight(.bold)).foregroundStyle(.duoWolf)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.duoPolar))
    }

    // MARK: - Bits

    private func scoreBadge(_ score: Int, size: CGFloat) -> some View {
        Text("\(score)")
            .font(.system(size: size * 0.4, weight: .heavy).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(scoreColor(score)))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 54)).foregroundStyle(.duoSwan)
            Text("Chưa có lịch sử").font(.title3.weight(.heavy)).foregroundStyle(.duoInk)
            Text("Hoàn thành một session rồi bắt đầu session mới để lưu lại và so sánh.")
                .font(.callout.weight(.medium)).foregroundStyle(.duoWolf)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
    }

    private func scoreColor(_ s: Int) -> Color { s >= 85 ? .duoGreen : (s >= 60 ? .duoGold : .duoRed) }

    private func normalized(_ str: String) -> String {
        str.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
           .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Grouped data

private struct SessionGroup: Identifiable {
    let session: Int
    let date: Date
    let items: [Item]
    var id: Int { session }

    struct Item: Identifiable {
        let id: UUID
        let vietnamese: String
        let attempt: PracticeAttempt
    }

    /// Average AI score across this session's graded attempts.
    var average: Int {
        let scores = items.compactMap { $0.attempt.feedback?.score }
        guard !scores.isEmpty else { return 0 }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
}
