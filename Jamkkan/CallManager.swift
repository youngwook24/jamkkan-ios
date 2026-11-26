import Foundation
import UIKit
import CallKit
import AVFoundation

enum CallPhase: Equatable {
    case idle      // 설정 화면
    case standby   // 예약하고 기다리는 중
    case ringing   // 울리는 중
    case inCall    // 통화 중
    case ended     // 방금 끊음
}

/// 예약 → 울림 → 통화 → 종료 흐름과 실제 전화 화면(CallKit) 연동을 맡는다.
final class CallManager: NSObject, ObservableObject, CXProviderDelegate {
    static let shared = CallManager()

    @Published var phase: CallPhase = .idle
    @Published var fireDate: Date?
    @Published var callStart: Date?
    @Published var usingSystemUI = false
    @Published var speakerOn = false
    @Published var message: String?

    private let store = SettingsStore.shared
    private let audio = AudioService.shared
    private let provider: CXProvider
    private let controller = CXCallController()

    private var callUUID: UUID?
    private var fireTimer: Timer?
    private var missTimer: Timer?
    private var redialCount = 0

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - 예약

    /// delay를 주지 않으면 설정 화면에서 고른 시간을 쓴다.
    func arm(delay: Int? = nil) {
        guard phase == .idle else { return }
        redialCount = 0
        message = nil
        schedule(after: delay ?? store.effectiveDelay)
    }

    private func schedule(after seconds: Int) {
        audio.startKeepAlive()
        if seconds <= 0 {
            ring()
            return
        }
        // 앱 안 화면으로 울릴 때는 앱이 켜져 있어야 하므로 자동 잠금을 막는다.
        UIApplication.shared.isIdleTimerDisabled = (store.s.ringMode == .inApp)
        let date = Date().addingTimeInterval(TimeInterval(seconds))
        fireDate = date
        phase = .standby
        fireTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.ring()
        }
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    func ringNow() {
        guard phase == .standby else { return }
        ring()
    }

    func cancel() {
        guard phase == .standby else { return }
        reset(message: "예약을 취소했습니다.")
    }

    // MARK: - 울림

    private func ring() {
        fireTimer?.invalidate()
        fireTimer = nil
        fireDate = nil
        let inBackground = UIApplication.shared.applicationState != .active
        if store.s.ringMode == .system || inBackground {
            ringWithSystemUI()
        } else {
            ringInApp()
        }
    }

    private func ringWithSystemUI() {
        let uuid = UUID()
        callUUID = uuid
        usingSystemUI = true
        phase = .ringing
        audio.prepareCallSession()

        let name = store.displayName
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: name)
        update.localizedCallerName = name
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    // 집중 모드 등으로 시스템이 전화를 막은 경우
                    print("전화 표시 실패: \(error)")
                    self.callUUID = nil
                    self.usingSystemUI = false
                    if UIApplication.shared.applicationState == .active {
                        self.ringInApp()
                    } else {
                        self.reset(message: "아이폰이 전화를 막았습니다. 집중 모드가 켜져 있는지 확인해 주세요.")
                    }
                    return
                }
                self.audio.stopKeepAlive()
                self.startMissTimer()
            }
        }
    }

    private func ringInApp() {
        usingSystemUI = false
        phase = .ringing
        UIApplication.shared.isIdleTimerDisabled = true
        audio.stopKeepAlive()
        audio.startInAppRing(sound: store.s.inAppRingtone, vibrate: store.s.inAppVibrate)
        startMissTimer()
    }

    private func startMissTimer() {
        missTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
            self?.missed()
        }
        RunLoop.main.add(timer, forMode: .common)
        missTimer = timer
    }

    private func missed() {
        guard phase == .ringing else { return }
        if usingSystemUI, let uuid = callUUID {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
        } else {
            audio.stopInAppRing()
        }
        finishUnanswered(message: "받지 않아 부재중 전화로 끝났습니다.")
    }

    private func finishUnanswered(message text: String) {
        missTimer?.invalidate()
        missTimer = nil
        callUUID = nil
        usingSystemUI = false
        if store.s.redial && redialCount < 2 {
            redialCount += 1
            schedule(after: 60)
        } else {
            reset(message: text)
        }
    }

    // MARK: - 앱 안 화면에서 받기·거절

    func acceptInApp() {
        guard phase == .ringing, !usingSystemUI else { return }
        missTimer?.invalidate()
        missTimer = nil
        audio.stopInAppRing()
        audio.activateCallSession()
        beginCall()
        audio.startVoice(settings: store.s, lines: store.scriptLines)
    }

    func declineInApp() {
        guard phase == .ringing, !usingSystemUI else { return }
        audio.stopInAppRing()
        finishUnanswered(message: "전화를 거절했습니다.")
    }

    // MARK: - 통화

    private func beginCall() {
        phase = .inCall
        callStart = Date()
        speakerOn = false
        UIDevice.current.isProximityMonitoringEnabled = true
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        audio.setSpeaker(speakerOn)
    }

    func endCall() {
        guard phase == .inCall else { return }
        if usingSystemUI, let uuid = callUUID {
            let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
            controller.request(transaction) { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                    self.finishCall()
                }
            }
        } else {
            finishCall()
        }
    }

    private func finishCall() {
        guard phase == .inCall else { return }
        audio.stopVoice()
        UIDevice.current.isProximityMonitoringEnabled = false
        phase = .ended
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self, self.phase == .ended else { return }
            self.reset(message: nil)
        }
    }

    private func reset(message text: String?) {
        fireTimer?.invalidate()
        fireTimer = nil
        missTimer?.invalidate()
        missTimer = nil
        let wasSystemCall = usingSystemUI
        audio.stopAll()
        if !wasSystemCall {
            audio.deactivateSession()
        }
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isProximityMonitoringEnabled = false
        fireDate = nil
        callStart = nil
        callUUID = nil
        usingSystemUI = false
        speakerOn = false
        phase = .idle
        message = text
    }

    // MARK: - CXProviderDelegate (실제 전화 화면에서 누른 버튼)

    func providerDidReset(_ provider: CXProvider) {
        reset(message: nil)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        missTimer?.invalidate()
        missTimer = nil
        audio.prepareCallSession()
        beginCall()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        if phase == .ringing {
            finishUnanswered(message: "전화를 거절했습니다.")
        } else {
            finishCall()
        }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // 시스템이 통화 오디오를 켜 준 뒤에 목소리를 시작해야 수화기로 나온다.
        guard phase == .inCall else { return }
        audio.startVoice(settings: store.s, lines: store.scriptLines)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audio.stopVoice()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        action.fulfill()
    }
}
