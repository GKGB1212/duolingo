//
//  HistoryView.swift
//  ITBizEnglish
//
//  Recent translations. Tap to restore one back into the translator.
//

import SwiftUI

struct HistoryView: View {
    let store: FlashcardStore
    let onSelect: (TranslationResult) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Your recent translations will appear here.")
                )
            } else {
                List {
                    ForEach(store.history) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.vietnameseText)
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.duoInk)
                                    .lineLimit(2)
                                Text(result.englishOptions.professional)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.duoWolf)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        withAnimation { store.clearHistory() }
                    }
                }
            }
        }
    }
}
