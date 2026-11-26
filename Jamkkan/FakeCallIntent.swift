import AppIntents

/// 단축어 앱, 동작 버튼, 뒷면 탭, Siri에서 가짜 전화를 예약하는 동작
struct StartFakeCallIntent: AppIntent {
    static let title: LocalizedStringResource = "가짜 전화 받기"
    static let description: IntentDescription? = IntentDescription("설정해 둔 발신자로 가짜 전화를 예약합니다.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "몇 초 뒤에 울릴까요", default: 0)
    var delaySeconds: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        CallManager.shared.arm(delay: max(0, delaySeconds))
        return .result()
    }
}

struct JamkkanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFakeCallIntent(),
            phrases: [
                "\(.applicationName) 가짜 전화",
                "\(.applicationName)에서 전화 받기"
            ],
            shortTitle: "가짜 전화 받기",
            systemImageName: "phone.fill"
        )
    }
}
