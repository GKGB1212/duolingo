//
//  DeckWordEditorView.swift
//  ITBizEnglish
//
//  Edit or delete a single word in a course. Editing preserves learning
//  progress (correctCount / review schedule).
//

import SwiftUI

struct DeckWordEditorView: View {
    @Bindable var store: DeckStore
    let deckID: UUID
    let word: DeckWord
    @Environment(\.dismiss) private var dismiss

    @State private var en: String
    @State private var vi: String
    @State private var pron: String
    @State private var example: String

    init(store: DeckStore, deckID: UUID, word: DeckWord) {
        self.store = store
        self.deckID = deckID
        self.word = word
        _en = State(initialValue: word.word)
        _vi = State(initialValue: word.meaning)
        _pron = State(initialValue: word.pronunciation)
        _example = State(initialValue: word.example)
    }

    private var canSave: Bool {
        !en.trimmingCharacters(in: .whitespaces).isEmpty &&
        !vi.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("English") { TextField("Word", text: $en, axis: .vertical) }
                Section("Tiếng Việt") { TextField("Nghĩa", text: $vi, axis: .vertical) }
                Section("Pronunciation") { TextField("/.../", text: $pron) }
                Section("Example") { TextField("Example sentence", text: $example, axis: .vertical) }

                Section {
                    LabeledContent("Progress", value: word.isMastered ? "Mastered"
                                   : "\(word.correctCount)/\(DeckWord.masteryGoal)")
                    Button(role: .destructive) {
                        store.deleteWord(word.id, fromDeck: deckID)
                        dismiss()
                    } label: { Label("Delete word", systemImage: "trash") }
                }
            }
            .navigationTitle("Edit Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        var w = word
        w.word = en.trimmingCharacters(in: .whitespacesAndNewlines)
        w.meaning = vi.trimmingCharacters(in: .whitespacesAndNewlines)
        w.pronunciation = pron.trimmingCharacters(in: .whitespacesAndNewlines)
        w.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(w, inDeck: deckID)
        dismiss()
    }
}
