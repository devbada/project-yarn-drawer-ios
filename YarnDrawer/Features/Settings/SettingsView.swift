import SwiftUI

struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("설정")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-1.1)
                        .foregroundStyle(YDColor.ink)
                    Text("작업 환경과 로컬 데이터를 관리합니다.")
                        .font(.system(size: 14))
                        .foregroundStyle(YDColor.muted)
                }

                LazyVGrid(
                    columns: horizontalSizeClass == .regular
                        ? [GridItem(.adaptive(minimum: 300), spacing: 10)]
                        : [GridItem(.flexible())],
                    spacing: 10
                ) {
                    settingRow(
                        icon: .palette,
                        title: "표시 도구",
                        description: "기본 하이라이트 색상과 선 두께"
                    )
                    settingRow(
                        icon: .storage,
                        title: "로컬 저장 공간",
                        description: "도안 파일과 작업 데이터를 기기에 보관"
                    )
                    settingRow(
                        icon: .link,
                        title: "외부 링크",
                        description: "목적지 확인 후 시스템 브라우저에서 열기"
                    )
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : YDSpacing.x4)
            .padding(.vertical, horizontalSizeClass == .regular ? 28 : 22)
        }
    }

    private func settingRow(
        icon: YDIcon,
        title: String,
        description: String
    ) -> some View {
        Button {
        } label: {
            HStack(spacing: YDSpacing.x3) {
                YDIconView(icon: icon, size: 21)
                    .foregroundStyle(YDColor.wood3)
                    .frame(width: 42, height: 42)
                    .background(YDColor.cream2)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(YDColor.ink)
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(YDColor.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text("›")
                    .font(.system(size: 22))
                    .foregroundStyle(YDColor.muted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ydSurfaceCard()
    }
}

