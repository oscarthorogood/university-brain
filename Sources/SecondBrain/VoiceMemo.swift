import SwiftUI
import AVFoundation
import Speech

/// Records a voice memo into Unsorted and writes its transcript beside it as a Quick Note (transcribed on this Mac when it can be).
@MainActor @Observable final class VoiceRecorder {
    enum Stage: Equatable { case idle, recording, transcribing, saved(String), failed(String) }
    var stage = Stage.idle
    var elapsed = 0.0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var started = Date.now
    private var audio: URL?

    private var stamp: String { started.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".").replacingOccurrences(of: ",", with: "") }

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            stage = .failed("Microphone access is off. Turn it on for University Brain in System Settings → Privacy & Security → Microphone."); return
        }
        started = .now
        let url = Vault.root.appending(path: "Unsorted/Voice memo \(stamp).m4a")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard r.record() else { stage = .failed("Couldn’t start recording."); return }
            recorder = r; audio = url; elapsed = 0; stage = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 } }
        } catch { stage = .failed(error.localizedDescription) }
    }

    /// Stops, transcribes and files the note. `discard` throws the recording away instead.
    func stop(discard: Bool = false, store: Store) async {
        recorder?.stop(); timer?.invalidate(); recorder = nil
        guard let url = audio else { stage = .idle; return }
        if discard { try? FileManager.default.removeItem(at: url); audio = nil; stage = .idle; return }
        stage = .transcribing
        let text = await Self.transcribe(url)
        let title = "Voice memo " + started.formatted(.dateTime.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let body = (text.map { $0.isEmpty ? "_Nothing was picked up._" : $0 } ?? "_No transcript: speech recognition wasn’t available._") + "\n\nAudio: ![[\(url.lastPathComponent)]]\n"
        do {
            try "# \(title)\n\n\(body)".write(to: url.deletingPathExtension().appendingPathExtension("md"), atomically: true, encoding: .utf8)
            store.reload(); audio = nil
            stage = .saved(text == nil ? "Saved the audio to Unsorted. There was no transcript." : "Saved to Unsorted with a transcript.")
        } catch { stage = .failed(error.localizedDescription) }
    }

    /// On this Mac when the language model is installed, so nothing leaves it. nil when not allowed or not available.
    static func transcribe(_ url: URL) async -> String? {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized, let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) ?? SFSpeechRecognizer(), rec.isAvailable else { return nil }
        let req = SFSpeechURLRecognitionRequest(url: url)
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.shouldReportPartialResults = false
        return await withCheckedContinuation { c in
            var done = false
            _ = rec.recognitionTask(with: req) { result, error in
                guard !done else { return }
                if let r = result, r.isFinal { done = true; c.resume(returning: r.bestTranscription.formattedString) }
                else if error != nil { done = true; c.resume(returning: nil) }
            }
        }
    }
}

struct VoiceMemoSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rec = VoiceRecorder()
    var body: some View {
        VStack(spacing: 16) {
            Text("Voice memo").font(.system(size: 16, weight: .semibold))
            switch rec.stage {
            case .idle:
                Text("Records into Unsorted and writes what you said as a note beside it. Sorter files both when you sort.").font(.system(size: 12)).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                Button { Task { await rec.start() } } label: { Label("Start recording", systemImage: "mic.fill") }.buttonStyle(.glassAction(.control, prominent: true))
            case .recording:
                Text(Duration.seconds(rec.elapsed).formatted(.time(pattern: .minuteSecond))).font(.system(size: 34, weight: .light)).monospacedDigit()
                HStack {
                    Button { Task { await rec.stop(discard: true, store: store); dismiss() } } label: { Text("Discard") }.buttonStyle(.glassAction(.control))
                    Button { Task { await rec.stop(store: store) } } label: { Label("Stop and save", systemImage: "stop.fill") }.buttonStyle(.glassAction(.control, prominent: true))
                }
            case .transcribing:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Writing it up on this Mac…").foregroundStyle(Color.ink2) }
            case .saved(let s):
                Label(s, systemImage: "checkmark.circle.fill").foregroundStyle(Color(light: 0x2F8467, dark: 0x5CC39A)).font(.system(size: 13))
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(Color.redFG).font(.system(size: 12)).multilineTextAlignment(.leading)
                Button("Close") { dismiss() }
            }
        }
        .padding(24).frame(width: 380)
        .interactiveDismissDisabled(rec.stage == .recording || rec.stage == .transcribing)
    }
}

/// Starts macOS dictation in whatever text field has focus (the same as Edit → Start Dictation).
enum Dictation {
    @MainActor static func start() { NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil) }
}
