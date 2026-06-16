import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case symbols
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "보관함"
        case .symbols: "기호"
        case .settings: "설정"
        }
    }

    var subtitle: String {
        switch self {
        case .library: "내 도안 보관함"
        case .symbols: "기호 라이브러리"
        case .settings: "앱 설정"
        }
    }

    var icon: YDIcon {
        switch self {
        case .library: .library
        case .symbols: .star
        case .settings: .settings
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var section: AppSection = .library
    @State private var isImportSheetPresented = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .background(YDBrandBackground())
        .sheet(isPresented: $isImportSheetPresented) {
            PatternImportView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $store.selectedPattern) { pattern in
            PatternViewerView(pattern: pattern)
                .environmentObject(store)
        }
        .alert(
            "도안 등록 오류",
            isPresented: Binding(
                get: { store.importErrorMessage != nil && !isImportSheetPresented },
                set: { if !$0 { store.importErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                store.importErrorMessage = nil
            }
        } message: {
            Text(store.importErrorMessage ?? "")
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            topBar(showsAddButton: true)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            compactTabBar
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            regularSidebar
            VStack(spacing: 0) {
                topBar(showsAddButton: false)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .library:
            LibraryView()
        case .symbols:
            SymbolsView()
        case .settings:
            SettingsView()
        }
    }

    private func topBar(showsAddButton: Bool) -> some View {
        HStack(spacing: YDSpacing.x3) {
            BrandMarkView()
            VStack(alignment: .leading, spacing: 2) {
                Text("뜨개서랍")
                    .font(YDFont.font(size: 18, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                Text(section.subtitle)
                    .font(YDFont.font(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.muted)
            }
            Spacer()
            if showsAddButton {
                Button {
                    isImportSheetPresented = true
                } label: {
                    HStack(spacing: 7) {
                        YDIconView(icon: .plus, size: 19)
                        Text("도안 등록")
                    }
                    .frame(minHeight: YDLayout.minimumTouchTarget)
                    .padding(.horizontal, 15)
                    .font(YDFont.font(size: 14, weight: .heavy))
                    .foregroundStyle(YDColor.cream0)
                    .background(YDColor.yarn4)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? YDSpacing.x6 : 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YDColor.line)
                .frame(height: 1)
        }
    }

    private var compactTabBar: some View {
        HStack(spacing: YDSpacing.x2) {
            ForEach(AppSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 4) {
                        YDIconView(icon: item.icon, size: 23)
                        Text(item.title)
                            .font(YDFont.font(size: 11, weight: .bold))
                    }
                    .foregroundStyle(section == item ? YDColor.yarn4 : YDColor.muted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .background(section == item ? YDColor.surfaceGreen : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(YDColor.line)
                .frame(height: 1)
        }
    }

    private var regularSidebar: some View {
        VStack(spacing: 14) {
            BrandMarkView(size: 54)
                .padding(.top, 14)

            VStack(spacing: YDSpacing.x2) {
                ForEach(AppSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        VStack(spacing: 4) {
                            YDIconView(icon: item.icon, size: 23)
                            Text(item.title)
                                .font(YDFont.font(size: 11, weight: .bold))
                        }
                        .foregroundStyle(section == item ? YDColor.yarn4 : YDColor.muted)
                        .frame(width: 74, height: 58)
                        .background(section == item ? YDColor.surfaceGreen : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }

            Spacer()

            Button {
                isImportSheetPresented = true
            } label: {
                YDIconView(icon: .plus, size: 24)
                    .foregroundStyle(YDColor.cream0)
                    .frame(width: 58, height: 58)
                    .background(YDColor.yarn4)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(color: YDColor.wood3.opacity(0.09), radius: 17, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("도안 등록")
            .padding(.bottom, 14)
        }
        .frame(width: YDLayout.sidebarWidth)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(YDColor.line)
                .frame(width: 1)
        }
    }
}

