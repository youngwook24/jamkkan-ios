import SwiftUI

@main
struct JamkkanApp: App {
    @StateObject private var store = SettingsStore.shared
    @StateObject private var calls = CallManager.shared
    @StateObject private var audio = AudioService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(calls)
                .environmentObject(audio)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var calls: CallManager

    var body: some View {
        ZStack {
            SetupView()
            overlay
        }
        .animation(.easeInOut(duration: 0.2), value: calls.phase)
        .statusBarHidden(calls.phase == .standby)
    }

    @ViewBuilder
    private var overlay: some View {
        switch calls.phase {
        case .idle:
            EmptyView()
        case .standby:
            StandbyView()
        case .ringing:
            if calls.usingSystemUI {
                // 실제 전화 화면이 위에 뜨므로 뒤는 까맣게 둔다.
                Color.black.ignoresSafeArea()
            } else {
                IncomingCallView()
            }
        case .inCall, .ended:
            InCallView()
        }
    }
}
