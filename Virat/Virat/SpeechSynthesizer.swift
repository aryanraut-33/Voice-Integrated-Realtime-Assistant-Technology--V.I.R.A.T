// In SpeechSynthesizer.swift

import Foundation
import AVFoundation

// We still want the class to primarily live on the MainActor for its properties.
@MainActor
class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSynthesizer()
    // The synthesizer itself is still a non-sendable property, but because the class
    // is on the MainActor, Swift knows it's being accessed safely.
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isSpeaking: Bool = false
    
    override private init() {
        super.init()
        self.synthesizer.delegate = self
    }

    // These methods are called from the UI (which is on the main thread),
    // so they are already safe.
    func speak(_ text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        
        let utterance = AVSpeechUtterance(string: text)
        let rishiVoice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == "Rishi" }
        let indianVoice = AVSpeechSynthesisVoice.speechVoices().first { $0.language == "en-IN" }
        utterance.voice = rishiVoice ?? indianVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
    
    // --- CORRECTED DELEGATE METHODS ---
    
    // We explicitly mark these delegate methods as 'nonisolated' to satisfy the
    // protocol's requirement. The system will call these from a background thread.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Inside this non-isolated context, we must jump back to the MainActor
        // before we can safely update our @Published UI property.
        Task { @MainActor in
            self.isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
