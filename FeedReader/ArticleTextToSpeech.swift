//
//  ArticleTextToSpeech.swift
//  FeedReader
//
//  Text-to-speech engine for reading articles aloud using AVSpeechSynthesizer.
//  Supports play/pause/stop, adjustable rate/pitch/voice, per-language voice
//  selection, and sentence-level progress tracking.
//

import Foundation
import AVFoundation
import os.log

// MARK: - TTS Configuration

/// User-adjustable text-to-speech settings.
struct TTSSettings: Codable {
    /// Speech rate (0.0–1.0, default 0.5 = AVSpeechUtteranceDefaultSpeechRate).
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    /// Pitch multiplier (0.5–2.0, default 1.0).
    var pitch: Float = 1.0
    /// Volume (0.0–1.0, default 1.0).
    var volume: Float = 1.0
    /// BCP-47 voice identifier (nil = system default for detected language).
    var preferredVoiceIdentifier: String? = nil
    /// Whether to read the title before the body.
    var readTitle: Bool = true
    /// Pause duration between title and body (seconds).
    var titlePauseDuration: TimeInterval = 0.8

    static let rateRange: ClosedRange<Float> = AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate
    static let pitchRange: ClosedRange<Float> = 0.5...2.0
}

// MARK: - TTS State

/// Current state of the speech engine.
enum TTSState: Equatable {
    case idle
    case playing
    case paused
}

// MARK: - Delegate

/// Delegate for observing TTS events (progress, completion, errors).
protocol ArticleTextToSpeechDelegate: AnyObject {
    /// Called when the TTS state changes.
    func ttsDidChangeState(_ state: TTSState)
    /// Called as each sentence/utterance range is spoken (for highlighting).
    func ttsDidProgress(characterRange: NSRange, inFullText: String)
    /// Called when reading finishes (naturally or via stop).
    func ttsDidFinish()
    /// Called on error.
    func ttsDidFail(error: String)
}

// MARK: - ArticleTextToSpeech

/// Manages text-to-speech playback for article content.
/// Thread-safe: all mutations happen on the main queue via the
/// AVSpeechSynthesizerDelegate callbacks.
final class ArticleTextToSpeech: NSObject {

    // MARK: - Singleton

    static let shared = ArticleTextToSpeech()

    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var state: TTSState = .idle {
        didSet {
            if state != oldValue {
                delegate?.ttsDidChangeState(state)
            }
        }
    }

    weak var delegate: ArticleTextToSpeechDelegate?

    /// Current settings (persisted to UserDefaults).
    var settings: TTSSettings {
        get { loadSettings() }
        set { saveSettings(newValue) }
    }

    /// The full text currently being spoken (title + body).
    private(set) var currentText: String = ""
    /// The article link currently being read (for tracking).
    private(set) var currentArticleLink: String?

    private static let settingsKey = "TTSSettings"

    // MARK: - Init

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Start reading an article. Stops any current speech first.
    func speak(title: String, body: String, articleLink: String? = nil) {
        stop()

        let settings = self.settings
        var fullText = ""
        if settings.readTitle && !title.isEmpty {
            fullText = title + "\n\n" + body
        } else {
            fullText = body
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            delegate?.ttsDidFail(error: "No text to read.")
            return
        }

        currentText = fullText
        currentArticleLink = articleLink

        // Configure audio session for spoken audio
        configureAudioSession()

        // Split into sentences for better progress tracking.
        // AVSpeechSynthesizer handles one utterance at a time.
        let utterance = AVSpeechUtterance(string: fullText)
        utterance.rate = settings.rate
        utterance.pitchMultiplier = settings.pitch
        utterance.volume = settings.volume

        if let voiceId = settings.preferredVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            // Auto-detect language from text
            let detectedLang = detectLanguage(fullText)
            utterance.voice = AVSpeechSynthesisVoice(language: detectedLang)
        }

        synthesizer.speak(utterance)
        state = .playing
    }

    /// Speak a Story object directly.
    func speak(story: Story) {
        speak(title: story.title, body: story.body, articleLink: story.link)
    }

    /// Pause speech.
    func pause() {
        guard state == .playing else { return }
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
    }

    /// Resume speech.
    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .playing
    }

    /// Toggle play/pause.
    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .idle: break // Nothing to toggle; call speak() first
        }
    }

    /// Stop speech entirely.
    func stop() {
        guard state != .idle else { return }
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        currentText = ""
        currentArticleLink = nil
    }

    /// Whether TTS is currently active (playing or paused).
    var isActive: Bool {
        state != .idle
    }

    // MARK: - Voice Discovery

    /// All available voices on this device.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    /// Available voices for a specific language code (e.g., "en-US").
    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix(languageCode.lowercased())
        }
    }

    /// All unique language codes with available voices.
    static var availableLanguages: [String] {
        let langs = Set(AVSpeechSynthesisVoice.speechVoices().map { $0.language })
        return langs.sorted()
    }

    // MARK: - Private Helpers

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal; speech may still work
            os_log("Audio session config failed: %{private}s", log: FeedReaderLogger.tts, type: .error, error.localizedDescription)
        }
    }

    /// Simple language detection using NSLinguisticTagger.
    private func detectLanguage(_ text: String) -> String {
        let tagger = NSLinguisticTagger(tagSchemes: [.language], options: 0)
        tagger.string = String(text.prefix(500)) // Sample first 500 chars
        return tagger.dominantLanguage ?? "en-US"
    }

    // MARK: - Settings Persistence

    private func loadSettings() -> TTSSettings {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
              let s = try? JSONDecoder().decode(TTSSettings.self, from: data) else {
            return TTSSettings()
        }
        return s
    }

    private func saveSettings(_ s: TTSSettings) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ArticleTextToSpeech: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        delegate?.ttsDidProgress(characterRange: characterRange, inFullText: currentText)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        state = .idle
        currentText = ""
        currentArticleLink = nil
        delegate?.ttsDidFinish()

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        state = .idle
        currentText = ""
        currentArticleLink = nil
    }
}
