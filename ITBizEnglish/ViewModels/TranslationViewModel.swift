//
//  TranslationViewModel.swift
//  ITBizEnglish
//
//  MVVM view model for the Sentence Translator. Owns all UI state and
//  talks to the (mockable) translation service. Uses the @Observable macro
//  (iOS 17+) for fine-grained, boilerplate-free observation.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TranslationViewModel {

    // MARK: - Published State
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var translationResult: TranslationResult?

    /// Briefly set after a successful save so the UI can show a toast.
    var lastSavedTone: Tone?

    // MARK: - Configuration
    /// Soft character limit — used to drive the counter + disable Translate.
    let characterLimit = 280

    // MARK: - Dependencies
    private let service: TranslationServicing
    private let store: FlashcardStore       // translation history
    private let practice: PracticeStore     // "Save" → Self-Translate practice
    private var currentTask: Task<Void, Never>?

    /// Real translation via Gemini by default. Pass `MockTranslationService()`
    /// explicitly for previews/offline demos.
    init(service: TranslationServicing = GeminiTranslationService(),
         store: FlashcardStore,
         practice: PracticeStore) {
        self.service = service
        self.store = store
        self.practice = practice
    }

    /// True when a real Gemini key is configured (drives the status caption).
    var isUsingRealAI: Bool { AppConfiguration.hasGeminiKey }

    // MARK: - Derived State

    var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canTranslate: Bool {
        !trimmedInput.isEmpty && !isLoading && inputText.count <= characterLimit
    }

    var isOverLimit: Bool {
        inputText.count > characterLimit
    }

    var remainingCharacters: Int {
        characterLimit - inputText.count
    }

    // MARK: - Intents

    func translate() {
        guard canTranslate else { return }

        // Cancel any in-flight request before starting a new one.
        currentTask?.cancel()
        errorMessage = nil

        let text = trimmedInput
        isLoading = true

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.service.translate(text)
                guard !Task.isCancelled else { return }
                withAnimationIfPossible {
                    self.translationResult = result
                }
                self.store.addToHistory(result)
            } catch is CancellationError {
                // A newer request superseded this one — stay silent.
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func clear() {
        currentTask?.cancel()
        inputText = ""
        translationResult = nil
        errorMessage = nil
        isLoading = false
    }
 
    /// Loads a past translation back into the editor + result panel.
    func restore(_ result: TranslationResult) {
        inputText = result.vietnameseText
        translationResult = result
        errorMessage = nil
    }

    // MARK: - Saving to Self-Translate practice

    func isSaved(tone: Tone) -> Bool {
        guard let result = translationResult else { return false }
        return practice.containsSavedTranslation(
            vietnamese: result.vietnameseText,
            english: tone.text(from: result.englishOptions))
    }

    func toggleSave(tone: Tone) {
        guard let result = translationResult else { return }
        let nowSaved = practice.toggleSavedTranslation(
            vietnamese: result.vietnameseText,
            english: tone.text(from: result.englishOptions))
        if nowSaved { lastSavedTone = tone }
    }
}

/// Applies a spring animation when running on a real UI thread.
@MainActor
private func withAnimationIfPossible(_ body: () -> Void) {
    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
        body()
    }
}
