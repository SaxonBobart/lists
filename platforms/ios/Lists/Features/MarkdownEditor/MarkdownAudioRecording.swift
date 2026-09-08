import SwiftUI
import AVFAudio
import Observation

@MainActor @Observable
final class MarkdownAudioRecording: NSObject, AVAudioRecorderDelegate {
    static let shared = MarkdownAudioRecording()
    struct Session: Codable {
        let itemID: UUID
        let title: String
        let fileName: String
        let started: Date
    }
    private(set) var session: Session?
    private(set) var recording = false
    private(set) var busy = false
    private(set) var elapsed = 0.0
    private(set) var level = 0.0
    private(set) var recovered = false
    var message: String?
    var visibleDocuments: Set<UUID> = []
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    private var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ListsRecording", isDirectory: true) }
    private var manifest: URL { directory.appendingPathComponent("session.json") }
    var fileURL: URL? { session.map { directory.appendingPathComponent($0.fileName) } }

    private override init() {
        super.init()
        if let data = try? Data(contentsOf: manifest), let saved = try? JSONDecoder().decode(Session.self, from: data) {
            session = saved; recovered = true
            message = "Recovered recording. Save it to finish adding it to your document."
        }
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recording else { return }
                self.pause()
                self.message = "Recording interrupted. Resume when you’re ready."
            }
        }
    }
    func start(itemID: UUID, title: String) async throws -> String {
        guard session == nil else { throw RecordingError.alreadyRecording }
        guard await AVAudioApplication.requestRecordPermission() else { throw RecordingError.permission }
        MarkdownPlayback.shared.stop()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let value = Session(itemID: itemID, title: title, fileName: UUID().uuidString.lowercased() + ".m4a", started: .now)
        let url = directory.appendingPathComponent(value.fileName)
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .default)
        try audio.setActive(true)
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder.delegate = self; recorder.isMeteringEnabled = true
            try JSONEncoder().encode(value).write(to: manifest, options: .atomic)
            guard recorder.record() else { throw RecordingError.startFailed }
            self.recorder = recorder; session = value; recording = true; recovered = false; elapsed = 0; message = nil
            meterTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, let recorder = self.recorder else { return }
                    self.elapsed = recorder.currentTime
                    recorder.updateMeters()
                    self.level = max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 60) / 60))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            return "Attachments/" + value.fileName
        } catch {
            try? FileManager.default.removeItem(at: manifest)
            try? FileManager.default.removeItem(at: url)
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }
    func pause() { recorder?.pause(); recording = false }
    func resume() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            recording = recorder?.record() == true
            if recording { message = nil }
        } catch { message = error.localizedDescription }
    }
    func finish(store: ItemStore) async {
        guard !busy, let value = session, let fileURL else { return }
        busy = true; defer { busy = false }
        recorder?.stop(); recording = false; meterTask?.cancel(); recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        do {
            // A previous successful promotion may have been interrupted before manifest cleanup.
            if (try? await store.attachmentURL(for: "Attachments/" + value.fileName)) == nil {
                _ = try await store.importAttachment(fileURL: fileURL, preferredFileName: value.fileName)
            }
            try FileManager.default.removeItem(at: manifest)
            try? FileManager.default.removeItem(at: fileURL)
            session = nil; recovered = false; message = nil
        } catch { recovered = true; message = "Recording kept safely. Couldn’t save: " + error.localizedDescription }
    }
    func discard(store: ItemStore) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if let session, var item = store.items.first(where: { $0.id == session.itemID }) {
            for ref in MarkdownMediaReference.references(in: item.body).reversed() where MarkdownAttachmentIndex.canonicalPath(ref.path) == "Attachments/" + session.fileName {
                item.body = (item.body as NSString).replacingCharacters(in: ref.range, with: "")
            }
            do { try await store.update(item) }
            catch { message = "Couldn’t remove the recording reference. Recording kept safely."; return }
        }

        recorder?.stop(); recorder = nil; meterTask?.cancel(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        try? FileManager.default.removeItem(at: manifest)
        session = nil; message = nil; recovered = false
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.pause(); self?.message = "Recording stopped unexpectedly. Save the captured audio or try again." }
    }
    enum RecordingError: LocalizedError {
        case alreadyRecording, permission, startFailed
        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "Finish the current recording before starting another capture."
            case .permission: "Microphone access is off. Enable it for Lists in Settings to record audio."
            case .startFailed: "The microphone could not start recording."
            }
        }
    }
}

struct MarkdownRecordingStrip: View {
    let store: ItemStore
    @State private var capture = MarkdownAudioRecording.shared
    @State private var showingDiscard = false
    @State private var showingDocument = false
    var body: some View {
        if let session = capture.session {
            VStack(spacing: 4) {
                if let message = capture.message { Text(message).font(.caption).accessibilityIdentifier("recording.status") }
                HStack {
                    Button { showingDocument = true } label: {
                        VStack(alignment: .leading) {
                            Label(capture.recovered ? "Recovered recording" : (capture.recording ? "Recording" : "Paused"), systemImage: "mic.fill")
                            Text(session.title).font(.caption).lineLimit(1)
                        }
                    }.accessibilityIdentifier("recording.document")
                    Spacer()
                    Text(Duration.seconds(capture.elapsed).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                    if !capture.recovered {
                        Button(capture.recording ? "Pause" : "Resume", systemImage: capture.recording ? "pause.fill" : "record.circle") {
                            if capture.recording { capture.pause() } else { capture.resume() }
                        }.labelStyle(.iconOnly).accessibilityIdentifier("recording.pause")
                    }
                    Button(capture.busy ? "Saving…" : "Stop and Save", systemImage: "stop.fill") { Task { await capture.finish(store: store) } }
                        .labelStyle(.iconOnly).disabled(capture.busy).accessibilityIdentifier("recording.stop")
                    Button("Discard", systemImage: "trash") { showingDiscard = true }.labelStyle(.iconOnly).accessibilityIdentifier("recording.discard")
                }
                if capture.recording { ProgressView(value: capture.level).tint(.red).accessibilityLabel("Microphone level") }
            }
            .padding(12).background(.regularMaterial)
            .confirmationDialog("Discard this recording?", isPresented: $showingDiscard) {
                Button("Discard Recording", role: .destructive) { Task { await capture.discard(store: store) } }.accessibilityIdentifier("recording.discard.confirm")
                Button("Cancel", role: .cancel) {}.accessibilityIdentifier("recording.discard.cancel")
            }
            .sheet(isPresented: $showingDocument) {
                if let item = store.items.first(where: { $0.id == session.itemID }) {
                    NavigationStack { ItemDocumentView(item: item, store: store) }
                } else { ContentUnavailableView("Document unavailable", systemImage: "doc") }
            }
        }
    }
}
