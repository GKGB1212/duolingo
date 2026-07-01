//
//  OptionCard.swift
//  ITBizEnglish
//
//  A distinct card showing one English option (Casual or Professional)
//  with copy, save-to-flashcard, and listen (text-to-speech) actions.
//

import SwiftUI

struct OptionCard: View {
    let tone: Tone
    let text: String
    let isSaved: Bool
    let isSpeaking: Bool

    let onCopy: () -> Void
    let onSave: () -> Void
    let onSpeak: () -> Void
    var onSaveWords: () -> Void = {}
    /// When set, shows a "Ghép từ" button that opens the word-bank practice.
    var onPractice: (() -> Void)? = nil

    @State private var didCopy = false

    private var accent: Color { Theme.accent(for: tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(.duoInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.4)
            actionBar
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(accent, lineWidth: 2)
        )
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(accent, lineWidth: 2)
                .mask(Rectangle().frame(height: 4).frame(maxHeight: .infinity, alignment: .bottom))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: tone.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(tone.title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.duoInk)
                Text(tone.usageHint)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.duoWolf)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Listen / Text-to-speech
            iconButton(
                system: isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                label: isSpeaking ? "Stop" : "Listen",
                tint: accent,
                isActive: isSpeaking,
                action: onSpeak
            )

            // Copy with checkmark feedback
            iconButton(
                system: didCopy ? "checkmark" : "doc.on.doc",
                label: didCopy ? "Copied" : "Copy",
                tint: didCopy ? .duoGreen : accent,
                action: copy
            )

            // Save individual words into a vocabulary deck
            iconButton(
                system: "text.badge.plus",
                label: "Lưu từ",
                tint: accent,
                action: onSaveWords
            )

            // Practice rebuilding this sentence by tapping word tiles
            if let onPractice {
                iconButton(
                    system: "puzzlepiece.fill",
                    label: "Ghép từ",
                    tint: accent,
                    action: onPractice
                )
            }

            Spacer()

            // Save to flashcard
            Button(action: saveTapped) {
                Label(
                    isSaved ? "Saved" : "Save",
                    systemImage: isSaved ? "bookmark.fill" : "bookmark"
                )
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(isSaved ? .white : accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSaved ? AnyShapeStyle(accent)
                                      : AnyShapeStyle(accent.opacity(0.12)))
                )
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: isSaved)
        }
    }

    private func iconButton(system: String,
                            label: String,
                            tint: Color,
                            isActive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: system)
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(tint.opacity(isActive ? 0.20 : 0.10))
                )
                .symbolEffect(.bounce, value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Behavior

    private func copy() {
        onCopy()
        withAnimation(.snappy) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.snappy) { didCopy = false }
        }
    }

    private func saveTapped() {
        onSave()
    }
}

#Preview {
    OptionCard(
        tone: .professional,
        text: "I will complete this task by the end of the day.",
        isSaved: false,
        isSpeaking: false,
        onCopy: {}, onSave: {}, onSpeak: {}
    )
    .padding()
}
