//
//  SpeechSynthesizer.swift
//  ITBizEnglish
//
//  Tiny wrapper around AVSpeechSynthesizer so users can hear and practice
//  the English pronunciation of each option.
//

import AVFoundation
import AudioToolbox
import UIKit
import Observation

/// Duolingo-style feedback: real sound files + a haptic. Players are cached and
/// reused; the audio session is set so effects play even with the mute switch on.
enum SoundFX {
    private static var players: [String: AVAudioPlayer] = [:]
    private static var sessionReady = false

    private static func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private static func play(_ name: String) {
        prepareSession()
        if let existing = players[name] {
            existing.currentTime = 0
            existing.play()
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        players[name] = player
        player.play()
    }

    static func correct() {
        play("correct")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func wrong() {
        play("wrong")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func completed() {
        play("completed-lesson")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Light tap haptic for button / option presses.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// The English voices installed on the device + how to pick one. iOS ships a
/// robotic "compact" voice by default; nicer "Nâng cao / Cao cấp" voices are a
/// free one-time download in iOS Settings ▸ Trợ năng ▸ Nội dung nói ▸ Giọng nói.
enum EnglishVoices {
    /// All installed English voices, best quality first, then by accent + name.
    static func all() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                if a.quality.rawValue != b.quality.rawValue {
                    return a.quality.rawValue > b.quality.rawValue   // premium → enhanced → default
                }
                if a.language != b.language { return a.language < b.language }
                return a.name < b.name
            }
    }

    /// The voice the app should speak with: the user's pick if it's still
    /// installed, otherwise the best available English voice.
    static func resolved() -> AVSpeechSynthesisVoice? {
        if let id = AppSettings.shared.voiceIdentifier,
           let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return best()
    }

    /// Best default pick: highest-quality US English voice, else any English one.
    static func best() -> AVSpeechSynthesisVoice? {
        let voices = all()
        return voices.first { $0.language == "en-US" } ?? voices.first
    }

    /// "Mỹ", "Anh"… from a language code like "en-US".
    static func accentLabel(_ language: String) -> String {
        switch language {
        case "en-US": return "Mỹ"
        case "en-GB": return "Anh"
        case "en-AU": return "Úc"
        case "en-IE": return "Ireland"
        case "en-ZA": return "Nam Phi"
        case "en-IN": return "Ấn Độ"
        case "en-CA": return "Canada"
        case "en-NZ": return "New Zealand"
        case "en-SG": return "Singapore"
        default:      return language.replacingOccurrences(of: "en-", with: "")
        }
    }

    /// "Cao cấp" / "Nâng cao" / "Tiêu chuẩn" from a voice quality.
    static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:  return "Cao cấp"
        case .enhanced: return "Nâng cao"
        default:        return "Tiêu chuẩn"
        }
    }
}

@Observable
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    /// The id of the utterance currently speaking, so the UI can animate
    /// only the active speaker button.
    private(set) var speakingID: String?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` in US English. `id` lets the view know which button is active.
    func speak(_ text: String, id: String, rate: Float = 0.46) {
        // Tapping the active speaker stops it (toggle behavior).
        if speakingID == id {
            stop()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = EnglishVoices.resolved() ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0

        speakingID = id
        synthesizer.speak(utterance)
    }

    /// Speaks `text` with an explicit `voice` — used by the voice picker to let
    /// the user hear a candidate before choosing it.
    func preview(_ text: String, voice: AVSpeechSynthesisVoice, id: String, rate: Float = 0.46) {
        if speakingID == id {
            stop()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0

        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakingID = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speakingID = nil
    }
}
