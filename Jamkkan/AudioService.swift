import AVFoundation
import AudioToolbox

/// 벨소리, 진동, 통화 음성(AI 음성·녹음), 녹음, 백그라운드 유지를 맡는다.
final class AudioService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioService()

    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var micDenied = false
    @Published var caption = ""

    private let session = AVAudioSession.sharedInstance()
    private let synth = AVSpeechSynthesizer()

    private var keepPlayer: AVAudioPlayer?
    private var ringPlayer: AVAudioPlayer?
    private var filePlayer: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var vibrateTimer: Timer?

    private var lines: [String] = []
    private var lineIndex = 0
    private var scriptActive = false
    private var voiceToken = 0
    private var active = FakeCallSettings()

    private override init() {
        super.init()
        synth.delegate = self
        hasRecording = FileManager.default.fileExists(atPath: SettingsStore.recordingURL.path)
    }

    static func koreanVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ko") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    // MARK: - 예약 중 백그라운드 유지

    /// 소리 없는 오디오를 반복 재생해, 폰을 잠가도 예약 타이머가 살아 있게 한다.
    func startKeepAlive() {
        guard keepPlayer == nil,
              let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.play()
            keepPlayer = player
        } catch {
            print("keep-alive 실패: \(error)")
        }
    }

    func stopKeepAlive() {
        keepPlayer?.stop()
        keepPlayer = nil
    }

    // MARK: - 앱 안 화면용 벨소리와 진동

    func startInAppRing(sound: Bool, vibrate: Bool) {
        stopInAppRing()
        if sound, let url = Bundle.main.url(forResource: "ring", withExtension: "wav") {
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.play()
                ringPlayer = player
            } catch {
                print("벨소리 재생 실패: \(error)")
            }
        }
        if vibrate {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            let timer = Timer(timeInterval: 1.6, repeats: true) { _ in
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            RunLoop.main.add(timer, forMode: .common)
            vibrateTimer = timer
        }
    }

    func stopInAppRing() {
        ringPlayer?.stop()
        ringPlayer = nil
        vibrateTimer?.invalidate()
        vibrateTimer = nil
    }

    // MARK: - 통화용 오디오 세션 (수화기 출력)

    /// 실제 전화 화면(CallKit)에서는 시스템이 세션을 켜 주므로 종류만 맞춰 둔다.
    func prepareCallSession() {
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        } catch {
            print("통화 세션 준비 실패: \(error)")
        }
    }

    /// 앱 안 화면에서는 직접 세션을 켠다.
    func activateCallSession() {
        prepareCallSession()
        do {
            try session.setActive(true)
        } catch {
            print("통화 세션 켜기 실패: \(error)")
        }
    }

    func setSpeaker(_ on: Bool) {
        do {
            try session.overrideOutputAudioPort(on ? .speaker : .none)
        } catch {
            print("스피커 전환 실패: \(error)")
        }
    }

    func deactivateSession() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // 다른 소리가 재생 중이면 실패할 수 있다. 무시해도 된다.
        }
    }

    // MARK: - 통화 음성

    func startVoice(settings: FakeCallSettings, lines newLines: [String]) {
        stopVoice()
        voiceToken += 1
        let token = voiceToken
        active = settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self, token == self.voiceToken else { return }
            switch settings.voiceMode {
            case .silent:
                break
            case .recording:
                if self.playRecording() == false {
                    self.beginScript(newLines)
                }
            case .ai:
                self.beginScript(newLines)
            }
        }
    }

    func stopVoice() {
        voiceToken += 1
        scriptActive = false
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        filePlayer?.stop()
        filePlayer = nil
        previewPlayer?.stop()
        previewPlayer = nil
        caption = ""
    }

    private func playRecording() -> Bool {
        let url = SettingsStore.recordingURL
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.play()
        filePlayer = player
        return true
    }

    private func beginScript(_ newLines: [String]) {
        lines = newLines
        lineIndex = 0
        scriptActive = true
        speakNext()
    }

    private func speakNext() {
        guard scriptActive, lineIndex < lines.count else {
            caption = ""
            scriptActive = false
            return
        }
        let text = lines[lineIndex]
        caption = text
        synth.speak(makeUtterance(text))
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        if !active.voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: active.voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        }
        let rate = Double(AVSpeechUtteranceDefaultSpeechRate) * active.rate
        utterance.rate = Float(min(max(rate, 0.3), 0.7))
        utterance.pitchMultiplier = Float(min(max(active.pitch, 0.5), 2.0))
        return utterance
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.scriptActive else { return }
            self.lineIndex += 1
            self.caption = ""
            let token = self.voiceToken
            let gap = min(max(self.active.gap, 0.5), 10)
            DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
                guard let self = self, token == self.voiceToken, self.scriptActive else { return }
                self.speakNext()
            }
        }
    }

    // MARK: - 미리 듣기

    func previewSpeech(_ text: String, settings: FakeCallSettings) {
        stopVoice()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("미리 듣기 세션 실패: \(error)")
        }
        active = settings
        synth.speak(makeUtterance(text))
    }

    func previewRecording() {
        stopVoice()
        let url = SettingsStore.recordingURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            previewPlayer = player
        } catch {
            print("녹음 재생 실패: \(error)")
        }
    }

    // MARK: - 녹음

    func startRecording() {
        stopVoice()
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    self.micDenied = true
                    return
                }
                self.micDenied = false
                do {
                    try self.session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try self.session.setActive(true)
                    let format: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]
                    let newRecorder = try AVAudioRecorder(url: SettingsStore.recordingURL, settings: format)
                    newRecorder.record()
                    self.recorder = newRecorder
                    self.isRecording = true
                } catch {
                    print("녹음 시작 실패: \(error)")
                    self.isRecording = false
                }
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        hasRecording = FileManager.default.fileExists(atPath: SettingsStore.recordingURL.path)
        deactivateSession()
    }

    func deleteRecording() {
        stopVoice()
        try? FileManager.default.removeItem(at: SettingsStore.recordingURL)
        hasRecording = false
    }

    // MARK: - 전체 정리

    func stopAll() {
        stopVoice()
        stopInAppRing()
        stopKeepAlive()
    }
}
