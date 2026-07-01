# ITBizEnglish 🇻🇳 → 🇬🇧

A SwiftUI app to learn **IT Business English** while working at a global tech
company. Core feature: the **Sentence Translator** — type a Vietnamese sentence
and get two English registers back:

- **Casual** — for Slack / Teams chat
- **Professional** — for Scrum meetings / Emails

## Open it

```bash
open ~/Desktop/ITBizEnglish/ITBizEnglish.xcodeproj
```

Press **⌘R** to run (iOS 17+ simulator). Everything works today via a mock
translation service — no API key needed.

> If Xcode complains about signing, select the target → **Signing & Capabilities**
> → pick your personal Team. To run only in the simulator you can leave it as-is.

## Architecture (MVVM)

| Layer | File | Role |
|-------|------|------|
| **Model** | `Models/TranslationResult.swift` | `Codable` + `Identifiable`, matches the API JSON |
| **ViewModel** | `ViewModels/TranslationViewModel.swift` | `@Observable`, owns `inputText` / `isLoading` / `errorMessage` / `translationResult` |
| **Service** | `Services/TranslationService.swift` | `TranslationServicing` protocol + `MockTranslationService` (1.2s delay) + `LiveTranslationService` stub |
| **Store** | `Services/FlashcardStore.swift` | Saved flashcards + history (UserDefaults) |
| **Views** | `Views/*` | `TranslationView`, `FlashcardsView`, `HistoryView` |
| **Components** | `Views/Components/*` | `OptionCard`, `TagCapsule` / `TagFlow`, `FlowLayout` |

## Features

- ✨ Apple-style UI: `GroupBox` cards, continuous corners, SF Symbols, gradients
- ⏳ Beautiful loading state (skeleton + shimmer) and inline error card
- 📋 **Copy** button with checkmark feedback + haptics
- 🔖 **Save to Flashcard** (toggle), shared live with the Flashcards tab
- 🔊 **Listen** — text-to-speech (AVSpeechSynthesizer) to practice pronunciation
- 🏷️ Generated **tags** as wrapping capsules (`FlowLayout`)
- 🕘 **History** of recent translations, tap to restore
- 🔢 Character limit + live counter

## Plug in the real API

`TranslationViewModel` depends only on the `TranslationServicing` protocol.
Fill in `LiveTranslationService` (endpoint, auth, request body) and swap it in:

```swift
// RootView.swift
TranslationView(
    store: store,
    // pass a service into the VM init if you wire it through
)
```

The mock already decodes from a real JSON string, so the network path is identical.
