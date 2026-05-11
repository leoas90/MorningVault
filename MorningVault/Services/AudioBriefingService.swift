import AVFoundation
import Combine

/// Audio-forward briefing player using AVFoundation speech synthesis.
/// Provides full playback control over AI-generated briefing content.
@MainActor
final class AudioBriefingService: ObservableObject {
    static let shared = AudioBriefingService()

    // MARK: - Published State
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentSectionIndex = 0
    @Published private(set) var progress: Double = 0  // 0.0 to 1.0
    @Published private(set) var currentWordIndex: Int = 0
    @Published private(set) var totalWords: Int = 0
    @Published private(set) var estimatedSecondsRemaining: Int = 0
    @Published var rate: Float = 0.52  // Default rate — 0.52 is natural default

    // MARK: - Private State
    private let synthesizer = AVSpeechSynthesizer()
    private var sections: [BriefingSection] = []
    private var fullText: String = ""
    private var wordRanges: [NSRange] = []
    private var currentUtteranceRange: NSRange = .init()

    // Rate presets (AVSpeechUtteranceDefaultRate ≈ 0.5)
    var ratePresets: [(label: String, value: Float)] {
        [
            ("0.75x", 0.38),
            ("1x", 0.52),
            ("1.25x", 0.62),
            ("1.5x", 0.72)
        ]
    }

    // MARK: - Init

    private init() {
        synthesizer.delegate = SpeechDelegateHandler.shared
        SpeechDelegateHandler.shared.onWord = { [weak self] range, utteranceRange in
            Task { @MainActor in
                self?.handleWord(range: range, utteranceRange: utteranceRange)
            }
        }
        SpeechDelegateHandler.shared.onFinish = { [weak self] in
            Task { @MainActor in
                self?.handleFinish()
            }
        }
    }

    // MARK: - Public API

    /// Load briefing sections and prepare for playback
    func load(sections: [BriefingSection]) {
        self.sections = sections
        self.currentSectionIndex = 0
        self.progress = 0
        self.currentWordIndex = 0

        // Build combined text from all sections
        let texts = sections.map { section in
            "\(section.icon) \(section.title). \(section.content)"
        }
        fullText = texts.joined(separator: ".\n\n")

        // Pre-compute word ranges for progress tracking
        wordRanges = computeWordRanges(fullText)
        totalWords = wordRanges.count
        estimatedSecondsRemaining = computeEstimatedSeconds()
    }

    private func computeWordRanges(_ text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, range, _, _ in
            ranges.append(NSRange(range, in: text))
        }
        return ranges
    }

    private func computeEstimatedSeconds() -> Int {
        // ~150 words per minute at default rate
        let wordsPerMinute = Double(150) * Double(rate) / 0.52
        return Int(Double(totalWords) / wordsPerMinute * 60)
    }

    /// Start or resume playback
    func play() {
        guard !sections.isEmpty else { return }

        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            isPlaying = true
        } else {
            speakSection(at: currentSectionIndex)
            isPlaying = true
            isPaused = false
        }
    }

    /// Pause playback
    func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        isPaused = true
        isPlaying = false
    }

    /// Stop and reset playback
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        currentSectionIndex = 0
        progress = 0
        currentWordIndex = 0
    }

    /// Skip to next section
    func nextSection() {
        guard currentSectionIndex < sections.count - 1 else { return }
        synthesizer.stopSpeaking(at: .immediate)
        currentSectionIndex += 1
        speakSection(at: currentSectionIndex)
    }

    /// Skip to previous section
    func previousSection() {
        if currentWordIndex > 5 {
            // Restart current section
            synthesizer.stopSpeaking(at: .immediate)
            speakSection(at: currentSectionIndex)
        } else if currentSectionIndex > 0 {
            // Go to previous section
            synthesizer.stopSpeaking(at: .immediate)
            currentSectionIndex -= 1
            speakSection(at: currentSectionIndex)
        }
    }

    /// Set playback rate
    func setRate(_ newRate: Float) {
        rate = newRate
        // If currently playing, restart current section with new rate
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            speakSection(at: currentSectionIndex)
        }
    }

    // MARK: - Private

    private func speakSection(at index: Int) {
        guard index < sections.count else {
            handleFinish()
            return
        }

        let section = sections[index]
        let text = "\(section.icon) \(section.title). \(section.content)"

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use high-quality voice if available
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        currentUtteranceRange = NSRange(location: 0, length: text.count)
        synthesizer.speak(utterance)
    }

    private func handleWord(range: NSRange, utteranceRange: NSRange) {
        // Track word progress across entire briefing
        if let globalIndex = wordRanges.firstIndex(where: { NSIntersectionRange($0, range).length > 0 }) {
            currentWordIndex = globalIndex
            progress = Double(globalIndex) / Double(max(totalWords, 1))
            estimatedSecondsRemaining = computeEstimatedSeconds()
        }
    }

    private func handleFinish() {
        if currentSectionIndex < sections.count - 1 {
            currentSectionIndex += 1
            speakSection(at: currentSectionIndex)
        } else {
            isPlaying = false
            isPaused = false
            progress = 1.0
            currentWordIndex = totalWords
        }
    }

    var currentSectionTitle: String {
        guard currentSectionIndex < sections.count else { return "" }
        return sections[currentSectionIndex].title
    }

    var totalSections: Int { sections.count }
}

// MARK: - Delegate Handler (non-isolated for AVFoundation)

final class SpeechDelegateHandler: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechDelegateHandler()

    var onWord: ((NSRange, NSRange) -> Void)?
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {}

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        onWord?(characterRange, NSRange(location: 0, length: utterance.speechString.count))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {}
}