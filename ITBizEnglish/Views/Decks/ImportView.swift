//
//  ImportView.swift
//  ITBizEnglish
//
//  Two ways to add words to a deck:
//   1. Paste bulk JSON ([{ "word", "meaning", "pronunciation?", "example?" }]).
//   2. ✨ AI mode — type simple words (one per line) and let Gemini fill in the
//      meaning, pronunciation and example automatically.
//

import SwiftUI

struct ImportView: View {
    @Bindable var store: DeckStore
    /// When set, import goes straight into this deck (no destination picker).
    var fixedDeckID: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable { case json = "JSON", ai = "AI ✨"; var id: String { rawValue } }
    @State private var mode: Mode = .json

    @State private var jsonText = ""
    @State private var aiText = ""
    @State private var newDeckTitle = ""
    @State private var selectedDeckID: UUID?

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var destinationDeckID: UUID? { fixedDeckID ?? selectedDeckID }

    var body: some View {
        NavigationStack {
            Form {
                if fixedDeckID == nil { destinationSection }

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .json: jsonSection
                case .ai:   aiSection
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
            }
            .navigationTitle("Add Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: run) {
                        if isWorking { ProgressView() } else { Text("Import") }
                    }
                    .disabled(isWorking || !canImport)
                }
            }
        }
    }

    // MARK: - Sections

    private var destinationSection: some View {
        Section("Destination") {
            Picker("Deck", selection: $selectedDeckID) {
                Text("➕ New deck").tag(UUID?.none)
                ForEach(store.decks) { deck in
                    Text(deck.title).tag(UUID?.some(deck.id))
                }
            }
            if destinationDeckID == nil {
                TextField("New deck title", text: $newDeckTitle)
            }
        }
    }

    private var jsonSection: some View {
        Section {
            TextEditor(text: $jsonText)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 180)
            Button("Insert example") { jsonText = Self.exampleJSON }
                .font(.caption)
        } header: {
            Text("Paste JSON array")
        } footer: {
            Text("Format: [{\"word\":\"deploy\",\"meaning\":\"triển khai\",\"pronunciation\":\"/dɪˈplɔɪ/\",\"example\":\"We deploy on Fridays.\"}]")
        }
    }

    private var aiSection: some View {
        Section {
            TextEditor(text: $aiText)
                .frame(minHeight: 160)
        } header: {
            Text("One word/phrase per line")
        } footer: {
            Text(AppConfiguration.hasGeminiKey
                 ? "Gemini will fill in meaning, pronunciation and an example for each line. English or Vietnamese both work."
                 : "⚠️ No Gemini key set. Add it in Configuration.plist to use AI mode.")
        }
    }

    // MARK: - Logic

    private var canImport: Bool {
        switch mode {
        case .json: return !jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ai:   return !aiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && AppConfiguration.hasGeminiKey
        }
    }

    private func run() {
        errorMessage = nil
        successMessage = nil

        switch mode {
        case .json:
            do {
                let deck = try store.importWords(fromJSON: jsonText,
                                                 intoDeck: destinationDeckID,
                                                 newDeckTitle: newDeckTitle)
                finish(count: deck.words.count, deckTitle: deck.title, appended: true)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

        case .ai:
            isWorking = true
            Task {
                do {
                    let words = try await DeckAIService().generateWords(from: aiText)
                    await MainActor.run {
                        commit(words)
                        isWorking = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        isWorking = false
                    }
                }
            }
        }
    }

    /// Adds AI-generated words to the chosen deck (creating one if needed).
    private func commit(_ words: [DeckWord]) {
        if let id = destinationDeckID, store.deck(id: id) != nil {
            store.addWords(words, toDeck: id)
            finish(count: words.count, deckTitle: store.deck(id: id)?.title ?? "", appended: false)
        } else {
            let title = newDeckTitle.isEmpty ? "AI Deck" : newDeckTitle
            let deck = store.createDeck(title: title)
            store.addWords(words, toDeck: deck.id)
            finish(count: words.count, deckTitle: title, appended: false)
        }
    }

    private func finish(count: Int, deckTitle: String, appended: Bool) {
        successMessage = "Added \(count) word\(count == 1 ? "" : "s") to “\(deckTitle)”."
        jsonText = ""; aiText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
    }

    private static let exampleJSON = """
    [
      {"word": "blocker", "meaning": "việc cản trở", "pronunciation": "/ˈblɒkə/", "example": "I have a blocker."},
      {"word": "to deploy", "meaning": "triển khai", "pronunciation": "/dɪˈplɔɪ/", "example": "We deploy on Fridays."}
    ]
    """
}

#Preview {
    ImportView(store: DeckStore())
}
