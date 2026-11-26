import SwiftUI
import PhotosUI
import AVFoundation

/// 설정 화면: 언제, 누가, 무슨 말, 어떻게 울릴지 고르고 예약한다.
struct SetupView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var calls: CallManager
    @EnvironmentObject private var audio: AudioService

    @State private var photoItem: PhotosPickerItem?
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                whenSection
                whoSection
                voiceSection
                ringSection
                extraSection
                shortcutSection
            }
            .navigationTitle("잠깐만요")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { launchBar }
            .onAppear { voices = AudioService.koreanVoices() }
            .onChange(of: photoItem) { _, item in
                loadPhoto(item)
            }
            .alert("알림", isPresented: messageShown) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(calls.message ?? "")
            }
        }
    }

    private var messageShown: Binding<Bool> {
        Binding(
            get: { calls.message != nil },
            set: { shown in
                if !shown { calls.message = nil }
            }
        )
    }

    // MARK: - 미리보기

    private var previewSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(store.displayLabel)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(CallStyle.decline, in: Circle())
                Image(systemName: "phone.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(CallStyle.accept, in: Circle())
            }
            .padding(16)
            .background(CallStyle.gradient(for: store.displayName), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        } footer: {
            Text(previewNote)
        }
    }

    private var previewNote: String {
        let words = store.delayWords
        if words.isEmpty {
            return "아래 버튼을 누르면 바로 이 사람에게서 전화가 옵니다."
        }
        return "아래 버튼을 누르면 \(words) 이 사람에게서 전화가 옵니다."
    }

    // MARK: - 언제

    private var whenSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Presets.delays) { option in
                    Button(option.title) {
                        store.s.useCustomDelay = false
                        store.s.delaySeconds = option.seconds
                    }
                    .buttonStyle(ChipStyle(selected: !store.s.useCustomDelay && store.s.delaySeconds == option.seconds, fill: true))
                }
                Button("직접") {
                    store.s.useCustomDelay = true
                }
                .buttonStyle(ChipStyle(selected: store.s.useCustomDelay, fill: true))
            }
            .padding(.vertical, 4)
            if store.s.useCustomDelay {
                Stepper("\(store.s.customMinutes)분 뒤", value: $store.s.customMinutes, in: 1...120)
            }
        } header: {
            Text("언제 울릴까요")
        }
    }

    // MARK: - 누가

    private var whoSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Presets.callers) { caller in
                        Button(caller.name) {
                            store.s.callerName = caller.name
                            store.s.callerLabel = caller.label
                            if let preset = Presets.script(id: caller.scriptID) {
                                store.s.script = preset.text
                            }
                        }
                        .buttonStyle(ChipStyle(selected: store.s.callerName == caller.name))
                    }
                }
                .padding(.vertical, 4)
            }
            TextField("화면에 뜨는 이름", text: $store.s.callerName)
            TextField("이름 아래 표시 (예: 휴대전화)", text: $store.s.callerLabel)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(store.s.photoData == nil ? "사진 넣기" : "사진 바꾸기", systemImage: "photo")
            }
            if store.s.photoData != nil {
                Button("사진 빼기", role: .destructive) {
                    store.s.photoData = nil
                    photoItem = nil
                }
            }
        } header: {
            Text("누가 걸까요")
        } footer: {
            Text("사진과 이름 아래 표시는 앱 안 화면으로 울릴 때 보입니다. 실제 전화 화면에는 이름만 나옵니다.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            let jpeg = image.squareThumbnail(side: 264).jpegData(compressionQuality: 0.82)
            await MainActor.run {
                store.s.photoData = jpeg
            }
        }
    }

    // MARK: - 무슨 말

    private var voiceSection: some View {
        Section {
            Picker("받은 뒤 소리", selection: $store.s.voiceMode) {
                ForEach(VoiceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch store.s.voiceMode {
            case .ai:
                aiRows
            case .recording:
                recordingRows
            case .silent:
                Text("받아도 아무 소리가 나지 않습니다. 통화하는 척만 하면 됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("받으면 무슨 말을 할까요")
        } footer: {
            Text("목소리는 실제 통화처럼 수화기에서 나옵니다. 크기는 통화 중에 측면 음량 버튼으로 조절하세요.")
        }
    }

    @ViewBuilder
    private var aiRows: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Presets.scripts) { preset in
                    Button(preset.title) {
                        store.s.script = preset.text
                    }
                    .buttonStyle(ChipStyle(selected: store.s.script == preset.text))
                }
            }
            .padding(.vertical, 4)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("대사 (한 줄이 한 마디, 줄 사이에 내가 대답할 틈이 생깁니다)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $store.s.script)
                .frame(minHeight: 140)
        }
        Picker("목소리 종류", selection: $store.s.voiceIdentifier) {
            Text("기본 한국어 음성").tag("")
            ForEach(voices, id: \.identifier) { voice in
                Text(voiceLabel(voice)).tag(voice.identifier)
            }
        }
        SliderRow(
            title: "말 빠르기",
            valueText: String(format: "%.2f배", store.s.rate),
            value: $store.s.rate,
            range: 0.8...1.3,
            step: 0.05
        )
        SliderRow(
            title: "음높이",
            valueText: String(format: "%.2f", store.s.pitch),
            value: $store.s.pitch,
            range: 0.7...1.4,
            step: 0.05
        )
        SliderRow(
            title: "대답할 틈",
            valueText: String(format: "%.1f초", store.s.gap),
            value: $store.s.gap,
            range: 1...6,
            step: 0.5
        )
        Button("첫 마디 미리 듣기") {
            hideKeyboard()
            if let first = store.scriptLines.first {
                audio.previewSpeech(first, settings: store.s)
            }
        }
        Toggle("통화 화면에 대사 자막 띄우기", isOn: $store.s.captions)
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) (프리미엄)"
        case .enhanced: return "\(voice.name) (고음질)"
        default: return voice.name
        }
    }

    @ViewBuilder
    private var recordingRows: some View {
        Button {
            if audio.isRecording {
                audio.stopRecording()
            } else {
                audio.startRecording()
            }
        } label: {
            Label(
                audio.isRecording ? "녹음 끝내기" : (audio.hasRecording ? "다시 녹음하기" : "녹음 시작"),
                systemImage: audio.isRecording ? "stop.circle.fill" : "mic.circle.fill"
            )
        }
        .tint(audio.isRecording ? Color.red : Color.accentColor)

        if audio.hasRecording && !audio.isRecording {
            Button("녹음 들어 보기") {
                audio.previewRecording()
            }
            Button("녹음 지우기", role: .destructive) {
                audio.deleteRecording()
            }
        }

        if audio.micDenied {
            Text("마이크 권한이 꺼져 있습니다. 설정 앱에서 이 앱의 마이크를 켜 주세요.")
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            Text(audio.hasRecording
                 ? "저장된 녹음이 있습니다. 전화를 받으면 처음부터 재생됩니다."
                 : "상대방이 할 말을 직접 녹음하세요. 말 사이에 대답할 틈을 두면 더 자연스럽습니다. 녹음이 없으면 AI 목소리로 대신합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 어떻게

    private var ringSection: some View {
        Section {
            Picker("울리는 방식", selection: $store.s.ringMode) {
                ForEach(RingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if store.s.ringMode == .inApp {
                Toggle("벨소리", isOn: $store.s.inAppRingtone)
                Toggle("진동", isOn: $store.s.inAppVibrate)
            }
        } header: {
            Text("어떻게 울릴까요")
        } footer: {
            Text(store.s.ringMode == .system
                 ? "아이폰의 실제 전화 화면으로 울립니다. 폰을 잠가 두거나 다른 앱을 쓰는 중에도 울리고, 벨소리와 진동은 폰 설정을 따릅니다."
                 : "앱 안의 전화 화면으로 울리며 발신자 사진이 보입니다. 앱을 켜 둔 상태여야 하고, 앱이 가려져 있으면 실제 전화 화면으로 대신 울립니다.")
        }
    }

    // MARK: - 추가

    private var extraSection: some View {
        Section {
            Toggle("기다리는 동안 화면 꺼진 척", isOn: $store.s.blackout)
            Toggle("안 받으면 1분 뒤 다시 전화", isOn: $store.s.redial)
        } header: {
            Text("더 그럴듯하게")
        } footer: {
            Text("화면 꺼진 척을 켜면 예약 중 화면이 새까맣게 보입니다. 두 번 두드리면 바로 울리고 길게 누르면 취소됩니다. 다시 전화는 두 번까지 걸려옵니다.")
        }
    }

    private var shortcutSection: some View {
        Section {
            Text("설정 앱의 동작 버튼 메뉴에서 단축어를 고르고 가짜 전화 받기를 지정하면, 버튼을 길게 눌러 바로 예약할 수 있습니다. 손쉬운 사용의 뒷면 탭에도 같은 단축어를 연결할 수 있습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("버튼 하나로 실행하기")
        }
    }

    // MARK: - 실행 버튼

    private var launchBar: some View {
        Button {
            hideKeyboard()
            calls.arm()
        } label: {
            Text(store.delayWords.isEmpty ? "지금 전화 받기" : "\(store.delayWords) 전화 받기")
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(CallStyle.accent)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}
