import SwiftUI

struct PatternCardView: View {
    let pattern: PatternItem
    let onOpen: () -> Void
    let onToggleFavorite: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                HStack(spacing: 0) {
                    PatternThumbnail(
                        style: pattern.thumbnailStyle,
                        symbol: pattern.symbol,
                        badge: pattern.fileBadge
                    )
                        .frame(width: YDLayout.thumbnailWidth)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(pattern.title)
                            .font(.system(size: 16, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(YDColor.ink)
                            .lineLimit(2)

                        Text(pattern.metadataLine)
                            .font(.system(size: 12))
                            .foregroundStyle(YDColor.muted)
                            .lineLimit(1)
                            .padding(.top, 6)

                        HStack(spacing: 5) {
                            ForEach(pattern.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(YDColor.muted)
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: 25)
                                    .background(YDColor.cream2)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 12)

                        HStack(spacing: YDSpacing.x2) {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(YDColor.cream2)
                                    Capsule()
                                        .fill(YDColor.yarn4)
                                        .frame(width: proxy.size.width * pattern.progress)
                                }
                            }
                            .frame(height: 6)

                            Text(pattern.progress >= 1 ? "완료" : "\(Int(pattern.progress * 100))%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(YDColor.muted)
                        }
                        .padding(.top, 12)
                    }
                    .padding(.leading, 15)
                    .padding(.trailing, 48)
                    .padding(.vertical, YDSpacing.x4)
                    .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pattern.title) 도안 열기")

            YDIconButton(
                icon: .star,
                accessibilityLabel: pattern.isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가",
                selected: pattern.isFavorite,
                action: onToggleFavorite
            )
            .scaleEffect(0.86)
            .padding(6)

            YDIconButton(
                icon: .more,
                accessibilityLabel: "\(pattern.title) 상세정보",
                action: onShowDetails
            )
            .scaleEffect(0.78)
            .padding(.trailing, 7)
            .padding(.top, 88)
        }
        .frame(minHeight: 142)
        .ydSurfaceCard()
    }
}

private struct PatternThumbnail: View {
    let style: PatternThumbnailStyle
    let symbol: String
    let badge: String

    private var colors: (Color, Color) {
        switch style {
        case .green:
            (Color(hex: 0xC9D36D), Color(hex: 0xDCE989))
        case .cream:
            (Color(hex: 0xE7D8BD), YDColor.cream2)
        case .wood:
            (Color(hex: 0xD8A45E), YDColor.wood1)
        }
    }

    var body: some View {
        ZStack {
            DiagonalStripePattern(colors: colors)
            Circle()
                .stroke(YDColor.cream0.opacity(0.66), lineWidth: 7)
                .frame(width: 62, height: 62)
                .overlay {
                    Text(symbol)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(YDColor.ink.opacity(0.75))
                }
            VStack {
                HStack {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(YDColor.cream0)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(YDColor.ink.opacity(0.84))
                        .clipShape(Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .clipped()
    }

}

private struct DiagonalStripePattern: View {
    let colors: (Color, Color)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colors.1))
            for offset in stride(from: -size.height, through: size.width, by: 18) {
                var stripe = Path()
                stripe.move(to: CGPoint(x: offset, y: size.height))
                stripe.addLine(to: CGPoint(x: offset + size.height, y: 0))
                context.stroke(stripe, with: .color(colors.0), lineWidth: 9)
            }
        }
    }
}
