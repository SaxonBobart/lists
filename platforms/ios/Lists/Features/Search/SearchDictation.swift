import Foundation
import AVFoundation
@preconcurrency import Speech

/// Explicit microphone activation only; recognition never falls back to a server.
@MainActor @Observable final class SearchDictation {
    private(set) var isListening = false
    var error: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()

    func start(onText: @escaping @MainActor (String) -> Void) async {
        stop()
        let token = UUID()
        generation = token
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token else { return }
        guard authorization == .authorized else {
            error = "Enable Speech Recognition for Lists in Settings to use voice search."
            return
        }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard generation == token else { return }
        guard allowed else {
            error = "Enable microphone access for Lists in Settings to use voice search."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            error = "On-device voice recognition is unavailable for your current language. You can still type your search."
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true)
            let engine = AVAudioEngine()
            self.engine = engine
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "SearchDictation", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let message = failure?.localizedDescription
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let text { onText(text) }
                    if finished || message != nil {
                        self.stop()
                        if let message, text == nil { self.error = message }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            stop()
            self.error = error.localizedDescription
        }
    }

    func stop() {
        generation = UUID()
        let hadAudio = engine != nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        if hadAudio { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
