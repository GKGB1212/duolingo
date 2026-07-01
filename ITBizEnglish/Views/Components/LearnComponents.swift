//
//  LearnComponents.swift
//  ITBizEnglish
//
//  Small reusable pieces for the learning screens: stat tiles, a progress
//  ring, and the big "study mode" buttons on the dashboard.
//

import SwiftUI

// MARK: - Stat tile

struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.heavy).monospacedDigit())
                .foregroundStyle(.duoInk)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.duoWolf)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .duoCard(cornerRadius: Theme.Radius.card)
    }
}

// MARK: - Mastery progress ring

struct MasteryRing: View {
    /// Fraction 0...1 of words that are mastered.
    let progress: Double
    let centerText: String
    let centerSubtitle: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.duoSwan, lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    Color.brand,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            VStack(spacing: 2) {
                Text(centerText)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.duoInk)
                    .contentTransition(.numericText())
                Text(centerSubtitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.duoWolf)
            }
        }
    }
}

// (StudyModeCard / MasteryBadge removed with the old Learn tab.)
