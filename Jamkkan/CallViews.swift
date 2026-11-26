import SwiftUI

private func clockText(_ seconds: Int) -> String {
    let safe = max(0, seconds)
    return String(format: "%02d:%02d", safe / 60, safe % 60)
}

/// 예약하고 기다리는 화면. 꺼진 척을 켜면 새까맣게 보인다.
struct StandbyView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var calls: CallManager

    @State private var peek = true
    @State private var peekCount = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                VStack(spacing: 18) {
                    Text(remaining(at: context.date))
                        .font(.system(size: 56, weight: .ultraLight))
                        .monospacedDigit()
                    Text("두 번 두드리면 바로 울립니다. 길게 누르면 취소됩니다.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    if store.s.ringMode == .system {
                        Text("폰을 잠가도 제시간에 울립니다.")
                            .font(.footnote)
                    }
                    HStack(spacing: 12) {
                        Button("지금 울리기") { calls.ringNow() }
                        Button("취소") { calls.cancel() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .foregroundStyle(.white)
                .padding(24)
            }
            .opacity(contentOpacity)
            .allowsHitTesting(!store.s.blackout || peek)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { calls.ringNow() }
        .onTapGesture { showPeek(seconds: 2.5) }
        .onLongPressGesture(minimumDuration: 0.9) { calls.cancel() }
        .onAppear { showPeek(seconds: 3.5) }
    }

    private var contentOpacity: Double {
        if !store.s.blackout { return 1 }
        return peek ? 0.6 : 0
    }

    private func remaining(at date: Date) -> String {
        guard let fire = calls.fireDate else { return "00:00" }
        return clockText(Int(fire.timeIntervalSince(date).rounded()))
    }

    private func showPeek(seconds: Double) {
        peekCount += 1
        let current = peekCount
        withAnimation(.easeOut(duration: 0.2)) { peek = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if current == peekCount {
                withAnimation(.easeIn(duration: 0.5)) { peek = false }
            }
        }
    }
}

/// 앱 안 수신 화면
struct IncomingCallView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var calls: CallManager

    @State private var pulse = false

    var body: some View {
        ZStack {
            CallStyle.gradient(for: store.displayName).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(store.displayLabel)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(store.displayName)
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("전화 수신 중")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 56)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.7 : 1)
                        .opacity(pulse ? 0 : 0.7)
                    AvatarView(size: 132)
                }

                Spacer()

                HStack {
                    CallRoundButton(symbol: "phone.down.fill", color: CallStyle.decline, title: "거절") {
                        calls.declineInApp()
                    }
                    Spacer()
                    CallRoundButton(symbol: "phone.fill", color: CallStyle.accept, title: "수락") {
                        calls.acceptInApp()
                    }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

/// 통화 중 화면. 실제 전화 화면으로 받았더라도 앱이 앞에 있으면 이 화면이 보인다.
struct InCallView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var calls: CallManager
    @EnvironmentObject private var audio: AudioService

    @State private var pressed: Set<String> = []

    private let decorative: [(id: String, symbol: String, title: String)] = [
        (id: "add", symbol: "plus", title: "통화 추가"),
        (id: "video", symbol: "video.fill", title: "영상통화"),
        (id: "contacts", symbol: "person.crop.circle", title: "연락처")
    ]

    var body: some View {
        ZStack {
            CallStyle.gradient(for: store.displayName).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(store.displayName)
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Text(timerText(at: context.date))
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.top, 56)

                Spacer()

                Text(captionText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)

                Spacer()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 18) {
                    PadButton(symbol: "mic.slash.fill", title: "음소거", active: pressed.contains("mute")) {
                        toggle("mute")
                    }
                    PadButton(symbol: "circle.grid.3x3.fill", title: "키패드", active: pressed.contains("keys")) {
                        toggle("keys")
                    }
                    PadButton(symbol: "speaker.wave.3.fill", title: "스피커", active: calls.speakerOn) {
                        calls.toggleSpeaker()
                    }
                    ForEach(decorative, id: \.id) { item in
                        PadButton(symbol: item.symbol, title: item.title, active: pressed.contains(item.id)) {
                            toggle(item.id)
                        }
                    }
                }
                .frame(maxWidth: 320)

                CallRoundButton(symbol: "phone.down.fill", color: CallStyle.decline) {
                    calls.endCall()
                }
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
            .padding(.horizontal, 24)
        }
    }

    private var captionText: String {
        store.s.captions ? audio.caption : ""
    }

    private func timerText(at date: Date) -> String {
        if calls.phase == .ended { return "통화 종료" }
        guard let start = calls.callStart else { return "00:00" }
        return clockText(Int(date.timeIntervalSince(start)))
    }

    private func toggle(_ id: String) {
        if pressed.contains(id) {
            pressed.remove(id)
        } else {
            pressed.insert(id)
        }
    }
}
