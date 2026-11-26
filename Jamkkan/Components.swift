import SwiftUI
import UIKit

/// 통화 화면 공통 스타일
enum CallStyle {
    static func hue(for name: String) -> Double {
        var value = 0
        for scalar in name.unicodeScalars {
            value = (value * 31 + Int(scalar.value)) % 360
        }
        return Double(value) / 360.0
    }

    static func gradient(for name: String) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: hue(for: name), saturation: 0.45, brightness: 0.30),
                Color(red: 0.035, green: 0.043, blue: 0.078)
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
    }

    static let accent = Color(red: 0.86, green: 0.29, blue: 0.13)
    static let accept = Color(red: 0.12, green: 0.62, blue: 0.34)
    static let decline = Color(red: 0.88, green: 0.22, blue: 0.23)
}

/// 발신자 사진 또는 이름 첫 글자
struct AvatarView: View {
    @EnvironmentObject private var store: SettingsStore
    let size: CGFloat

    var body: some View {
        Group {
            if let data = store.s.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(hue: CallStyle.hue(for: store.displayName), saturation: 0.42, brightness: 0.62)
                    Text(String(store.displayName.prefix(1)))
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// 선택형 알약 버튼
struct ChipStyle: ButtonStyle {
    let selected: Bool
    var fill: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 40)
            .background(selected ? Color.primary : Color(uiColor: .secondarySystemFill), in: Capsule())
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 제목, 현재 값, 슬라이더를 한 줄에 묶은 행
struct SliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

/// 수락·거절·종료용 둥근 버튼
struct CallRoundButton: View {
    let symbol: String
    let color: Color
    var title: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title ?? "통화 종료")
            if let title = title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

/// 통화 중 화면의 보조 버튼
struct PadButton: View {
    let symbol: String
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(active ? Color.black : Color.white)
                    .frame(width: 68, height: 68)
                    .background(active ? Color.white : Color.white.opacity(0.14), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

extension UIImage {
    /// 가운데를 기준으로 잘라 정사각형으로 줄인다.
    func squareThumbnail(side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let scale = max(side / size.width, side / size.height)
            let width = size.width * scale
            let height = size.height * scale
            draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
