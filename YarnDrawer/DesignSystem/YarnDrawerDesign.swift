import SwiftUI
import UIKit
import CoreText

enum YDColor {
    static let cream0 = Color(hex: 0xFFFDF7)
    static let cream1 = Color(hex: 0xFBF6E9)
    static let cream2 = Color(hex: 0xF3E8D1)
    static let cream3 = Color(hex: 0xE8D8B9)

    static let yarn1 = Color(hex: 0xDDEB86)
    static let yarn2 = Color(hex: 0xC8DB62)
    static let yarn3 = Color(hex: 0x9DAE43)
    static let yarn4 = Color(hex: 0x6F7C29)

    static let wood1 = Color(hex: 0xF1C878)
    static let wood2 = Color(hex: 0xC88B3F)
    static let wood3 = Color(hex: 0x79552A)

    static let ink = Color(hex: 0x30291D)
    static let muted = Color(hex: 0x776D5E)
    static let line = Color(hex: 0xE7D9BD)
    static let danger = Color(hex: 0x9B4E2C)
    static let focus = Color(hex: 0x246BCE)

    static let surfaceGreen = yarn1.opacity(0.28)
    static let currentRow = yarn1.opacity(0.60)
    static let highlight = wood1.opacity(0.42)
}

enum YDSpacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x12: CGFloat = 48
}

enum YDRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 18
    static let large: CGFloat = 26
}

enum YDLayout {
    static let minimumTouchTarget: CGFloat = 44
    static let sidebarWidth: CGFloat = 92
    static let thumbnailWidth: CGFloat = 112
}

enum YDFont {
    private static let fonts: [(file: String, name: String)] = [
        ("MaruBuri-ExtraLight", "MaruBuriot-ExtraLight"),
        ("MaruBuri-Light", "MaruBuriot-Light"),
        ("MaruBuri-Regular", "MaruBuriot-Regular"),
        ("MaruBuri-SemiBold", "MaruBuriot-SemiBold"),
        ("MaruBuri-Bold", "MaruBuriot-Bold")
    ]

    static func registerFonts() {
        fonts.forEach { font in
            guard
                UIFont(name: font.name, size: 12) == nil,
                let url = Bundle.main.url(
                    forResource: font.file,
                    withExtension: "otf",
                    subdirectory: "Fonts"
                )
            else {
                return
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func configureNavigationFonts() {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: uiFont(size: 17, weight: .semibold),
            .foregroundColor: UIColor(YDColor.ink)
        ]
        let largeTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: uiFont(size: 32, weight: .bold),
            .foregroundColor: UIColor(YDColor.ink)
        ]
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = titleAttributes
        appearance.largeTitleTextAttributes = largeTitleAttributes
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        let barButtonAttributes: [NSAttributedString.Key: Any] = [
            .font: uiFont(size: 17, weight: .semibold)
        ]
        UIBarButtonItem.appearance().setTitleTextAttributes(barButtonAttributes, for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes(barButtonAttributes, for: .highlighted)
        UIBarButtonItem.appearance().setTitleTextAttributes(barButtonAttributes, for: .disabled)

        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: uiFont(size: 13, weight: .semibold)],
            for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: uiFont(size: 13, weight: .bold)],
            for: .selected
        )
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(fontName(for: weight), size: size)
    }

    static func symbol(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: fontName(for: weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func fontName(for weight: Font.Weight) -> String {
        if weight == .ultraLight || weight == .thin {
            return "MaruBuriot-ExtraLight"
        }
        if weight == .light {
            return "MaruBuriot-Light"
        }
        if weight == .medium || weight == .semibold {
            return "MaruBuriot-SemiBold"
        }
        if weight == .bold || weight == .heavy || weight == .black {
            return "MaruBuriot-Bold"
        }
        return "MaruBuriot-Regular"
    }

    private static func fontName(for weight: UIFont.Weight) -> String {
        if weight == .ultraLight || weight == .thin {
            return "MaruBuriot-ExtraLight"
        }
        if weight == .light {
            return "MaruBuriot-Light"
        }
        if weight == .medium || weight == .semibold {
            return "MaruBuriot-SemiBold"
        }
        if weight == .bold || weight == .heavy || weight == .black {
            return "MaruBuriot-Bold"
        }
        return "MaruBuriot-Regular"
    }
}

enum YDIcon: String {
    case yarn = "IconYarn"
    case library = "IconLibrary"
    case star = "IconStar"
    case settings = "IconSettings"
    case plus = "IconPlus"
    case search = "IconSearch"
    case back = "IconBack"
    case highlight = "IconHighlight"
    case check = "IconCheck"
    case note = "IconNote"
    case row = "IconRow"
    case more = "IconMore"
    case upload = "IconUpload"
    case palette = "IconPalette"
    case storage = "IconStorage"
    case link = "IconLink"
}

struct YDIconView: View {
    let icon: YDIcon
    var size: CGFloat = 24

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct YDSurfaceCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(YDColor.cream0)
            .clipShape(RoundedRectangle(cornerRadius: YDRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: YDRadius.medium, style: .continuous)
                    .stroke(YDColor.line, lineWidth: 1)
            }
            .shadow(color: YDColor.wood3.opacity(0.09), radius: 17, y: 8)
    }
}

extension View {
    func ydSurfaceCard() -> some View {
        modifier(YDSurfaceCard())
    }
}

struct YDPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YDFont.font(size: 14, weight: .heavy))
            .foregroundStyle(YDColor.cream0)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.horizontal, YDSpacing.x4)
            .background(YDColor.yarn4.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct YDSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YDFont.font(size: 14, weight: .heavy))
            .foregroundStyle(YDColor.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.horizontal, YDSpacing.x4)
            .background(YDColor.cream0.opacity(configuration.isPressed ? 0.74 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(YDColor.line, lineWidth: 1)
            }
    }
}

struct YDIconButton: View {
    let icon: YDIcon
    let accessibilityLabel: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            YDIconView(icon: icon, size: selected ? 19 : 22)
                .foregroundStyle(selected ? YDColor.wood3 : YDColor.ink)
                .frame(width: YDLayout.minimumTouchTarget, height: YDLayout.minimumTouchTarget)
                .background(selected ? YDColor.wood1 : YDColor.cream0)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? YDColor.wood3 : YDColor.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct YDBrandBackground: View {
    var body: some View {
        ZStack {
            YDColor.cream1
            Circle()
                .fill(YDColor.yarn1.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -180, y: -300)
            Circle()
                .fill(YDColor.wood1.opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 78)
                .offset(x: 190, y: 340)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
