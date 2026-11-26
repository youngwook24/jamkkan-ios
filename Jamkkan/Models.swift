import Foundation

/// 전화를 받은 뒤 들리는 소리의 종류
enum VoiceMode: String, Codable, CaseIterable, Identifiable {
    case ai, recording, silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI 목소리"
        case .recording: return "내 녹음"
        case .silent: return "소리 없이"
        }
    }
}

/// 전화가 울리는 방식
enum RingMode: String, Codable, CaseIterable, Identifiable {
    case system, inApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "실제 전화 화면"
        case .inApp: return "앱 안 화면"
        }
    }
}

struct DelayOption: Identifiable {
    let seconds: Int
    let title: String
    var id: Int { seconds }
}

struct CallerPreset: Identifiable {
    let id: String
    let name: String
    let label: String
    let scriptID: String
}

struct ScriptPreset: Identifiable {
    let id: String
    let title: String
    let text: String
}

enum Presets {
    static let delays: [DelayOption] = [
        DelayOption(seconds: 0, title: "지금"),
        DelayOption(seconds: 10, title: "10초"),
        DelayOption(seconds: 60, title: "1분"),
        DelayOption(seconds: 180, title: "3분"),
        DelayOption(seconds: 300, title: "5분")
    ]

    static let callers: [CallerPreset] = [
        CallerPreset(id: "boss", name: "김 팀장", label: "휴대전화", scriptID: "work"),
        CallerPreset(id: "mom", name: "엄마", label: "휴대전화", scriptID: "family"),
        CallerPreset(id: "delivery", name: "택배기사님", label: "휴대전화", scriptID: "delivery"),
        CallerPreset(id: "clinic", name: "치과", label: "직장", scriptID: "clinic")
    ]

    static let scripts: [ScriptPreset] = [
        ScriptPreset(
            id: "work",
            title: "급한 업무",
            text: "여보세요, 지금 잠깐 통화 괜찮아요?\n아까 보낸 자료에 급하게 확인할 게 있어서요.\n숫자가 좀 안 맞는 것 같은데, 지금 바로 볼 수 있어요?\n네, 오래 안 걸려요. 자리 옮겨서 얘기해요."
        ),
        ScriptPreset(
            id: "family",
            title: "집안일",
            text: "어, 나야. 지금 잠깐 통화 돼?\n집에 일이 좀 생겨서 그래. 큰일은 아닌데 지금 얘기해야 할 것 같아.\n응, 조용한 데로 가서 다시 말해 줄래?\n그래, 기다릴게."
        ),
        ScriptPreset(
            id: "delivery",
            title: "택배",
            text: "안녕하세요, 택배인데요. 지금 댁에 안 계신가요?\n물건이 커서 문 앞에 두기가 어렵거든요.\n어디에 두면 될지 지금 알려 주시겠어요?\n네, 확인하고 다시 말씀해 주세요."
        ),
        ScriptPreset(
            id: "clinic",
            title: "예약 확인",
            text: "안녕하세요, 치과입니다. 예약 건으로 연락드렸어요.\n예약하신 시간에 변동이 생겨서요, 지금 일정 확인 가능하실까요?\n네, 달력 보시고 편한 시간 말씀해 주세요."
        )
    ]

    static func script(id: String) -> ScriptPreset? {
        scripts.first { $0.id == id }
    }
}

struct FakeCallSettings: Codable, Equatable {
    // 언제
    var delaySeconds: Int = 0
    var useCustomDelay: Bool = false
    var customMinutes: Int = 2

    // 누가
    var callerName: String = "김 팀장"
    var callerLabel: String = "휴대전화"
    var photoData: Data? = nil

    // 무슨 말
    var voiceMode: VoiceMode = .ai
    var script: String = Presets.scripts[0].text
    var voiceIdentifier: String = ""
    var rate: Double = 1.0
    var pitch: Double = 1.0
    var gap: Double = 2.5
    var captions: Bool = false

    // 어떻게
    var ringMode: RingMode = .system
    var inAppRingtone: Bool = true
    var inAppVibrate: Bool = true

    // 추가
    var blackout: Bool = true
    var redial: Bool = false
}

/// 설정을 기기에 저장하고 화면에 알리는 저장소
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var s: FakeCallSettings {
        didSet { save() }
    }

    private static let key = "jamkkan.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: SettingsStore.key),
           let saved = try? JSONDecoder().decode(FakeCallSettings.self, from: data) {
            s = saved
        } else {
            s = FakeCallSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: SettingsStore.key)
        }
    }

    var effectiveDelay: Int {
        s.useCustomDelay ? max(1, s.customMinutes) * 60 : s.delaySeconds
    }

    var delayWords: String {
        let seconds = effectiveDelay
        if seconds <= 0 { return "" }
        if seconds < 60 { return "\(seconds)초 뒤" }
        return "\(seconds / 60)분 뒤"
    }

    var displayName: String {
        let name = s.callerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "발신자 표시 없음" : name
    }

    var displayLabel: String {
        let label = s.callerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "휴대전화" : label
    }

    var scriptLines: [String] {
        s.script
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static var recordingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice.m4a")
    }
}
