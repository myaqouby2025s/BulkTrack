import SwiftUI

enum KeyboardControl {
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

private struct DismissibleKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .submitLabel(.done)
            .onSubmit { KeyboardControl.dismiss() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        KeyboardControl.dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Done editing. Hide keyboard")
                }
            }
    }
}

extension View {
    func dismissibleKeyboard() -> some View { modifier(DismissibleKeyboardModifier()) }
}

struct BulkTrackBrand: View {
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image("BulkTrackMark").resizable().scaledToFit()
                .frame(width: compact ? 28 : 48, height: compact ? 28 : 48)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 13, style: .continuous))
                .accessibilityHidden(true)
            Text("BULKTRACK").tracking(compact ? 1.5 : 2)
                .font(compact ? .caption.bold() : .headline.bold()).foregroundStyle(AppTheme.accent)
                .lineLimit(1)
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
    }
}

enum AppTheme {
    static let background = adaptive(0xF3F5F0, dark: 0x101917)
    static let surface = adaptive(0xFFFFFF, dark: 0x1A2723)
    static let ink = adaptive(0x183C33, dark: 0xEDF5EF)
    static let secondary = adaptive(0x61736B, dark: 0xA6B9AD)
    static let line = adaptive(0xE3EAE2, dark: 0x30423A)
    static let accent = adaptive(0x276C50, dark: 0xA6DFB7)
    static let hero = Color(hex: 0x173E32)
    static let lime = Color(hex: 0xD9F99A)
    static let sage = adaptive(0xE8F2E4, dark: 0x263D2C)
    static let blue = adaptive(0xE8F1FC, dark: 0x213349)
    static let blueInk = adaptive(0x285C91, dark: 0xABCEFB)
    static let peach = adaptive(0xFFF0E0, dark: 0x402F24)
    static let peachInk = adaptive(0x995A27, dark: 0xF9CDA1)
    static let lavender = adaptive(0xEFEAFB, dark: 0x342C46)
    static let lavenderInk = adaptive(0x695096, dark: 0xD6C5F4)

    private static func adaptive(_ light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

struct SurfaceCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(AppTheme.line, lineWidth: 1) }
    }
}

struct CardHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.headline, design: .default, weight: .semibold)).foregroundStyle(AppTheme.ink)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondary) }
        }
    }
}

struct IconBadge: View {
    let symbol: String
    let color: Color
    let background: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
            .foregroundStyle(color).frame(width: 42, height: 42)
            .background(background, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct PressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PrimaryAction: View {
    let title: String
    let symbol: String
    var onDark = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(onDark ? AppTheme.hero : Color.white)
                .background(onDark ? AppTheme.lime : AppTheme.hero, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(PressButtonStyle())
    }
}

struct SoftProgress: View {
    let value: Double
    let goal: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fraction: Double { min(1, max(0, value / max(goal, 1))) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.12))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 7)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(USUnits.number(fraction * 100)) percent")
    }
}

struct FuelRing: View {
    let value: Double
    let goal: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fraction = 0.0
    private var progress: Double { min(1, max(0, value / max(1, goal))) }
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
            Circle().trim(from: 0, to: fraction)
                .stroke(AppTheme.lime, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 5) {
                Image(systemName: "flame.fill").font(.title3).foregroundStyle(AppTheme.lime)
                Text("\(USUnits.number(progress * 100))%")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: 96, height: 96)
        .onAppear { fraction = progress }
        .onChange(of: progress) { _, newValue in fraction = newValue }
        .animation(reduceMotion ? nil : .smooth(duration: 0.65), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily calories")
        .accessibilityValue("\(USUnits.number(value)) of \(USUnits.number(goal)) calories")
    }
}

struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(AppTheme.accent)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(AppTheme.ink)
            Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
