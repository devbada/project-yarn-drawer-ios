import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var storageByteSize: Int64 = 0
    @State private var showsDeleteAllConfirmation = false
    @State private var showsAppInfo = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
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
                            description: "마지막 도구와 형광펜 색상 자동 복원"
                        ) {
                            showToast("표시 도구 설정은 뷰어에서 바로 변경합니다.")
                        }
                        settingRow(
                            icon: .storage,
                            title: "로컬 저장 공간",
                            description: ByteCountFormatter.string(
                                fromByteCount: storageByteSize,
                                countStyle: .file
                            )
                        ) {
                            refreshStorageUsage()
                        }
                        settingRow(
                            icon: .storage,
                            title: "데이터 전체 삭제",
                            description: "등록 도안과 작업 데이터를 모두 제거",
                            isDestructive: true
                        ) {
                            showsDeleteAllConfirmation = true
                        }
                        settingRow(
                            icon: .link,
                            title: "외부 링크",
                            description: "목적지 확인 후 시스템 브라우저에서 열기"
                        ) {
                            showToast("기호 화면에서 링크별 도메인을 확인합니다.")
                        }
                        settingRow(
                            icon: .settings,
                            title: "앱 정보",
                            description: "\(appVersion) · 라이선스"
                        ) {
                            showsAppInfo = true
                        }
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 36 : YDSpacing.x4)
                .padding(.vertical, horizontalSizeClass == .regular ? 28 : 22)
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(YDColor.cream0)
                    .padding(.horizontal, YDSpacing.x4)
                    .padding(.vertical, YDSpacing.x3)
                    .background(YDColor.ink.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, YDSpacing.x4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await loadStorageUsage()
        }
        .alert("모든 데이터를 삭제할까요?", isPresented: $showsDeleteAllConfirmation) {
            Button("취소", role: .cancel) {}
            Button("전체 삭제", role: .destructive) {
                deleteAllLocalData()
            }
        } message: {
            Text("등록한 도안, 원본 파일, 작업용 PDF, 표시, 페이지 복원 정보가 삭제됩니다. 샘플 도안은 다시 표시됩니다.")
        }
        .sheet(isPresented: $showsAppInfo) {
            AppInfoView(appVersion: appVersion)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func settingRow(
        icon: YDIcon,
        title: String,
        description: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: YDSpacing.x3) {
                YDIconView(icon: icon, size: 21)
                    .foregroundStyle(isDestructive ? YDColor.danger : YDColor.wood3)
                    .frame(width: 42, height: 42)
                    .background(isDestructive ? YDColor.danger.opacity(0.08) : YDColor.cream2)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isDestructive ? YDColor.danger : YDColor.ink)
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

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshStorageUsage() {
        Task {
            await loadStorageUsage()
            showToast("저장 공간 사용량을 갱신했습니다.")
        }
    }

    private func loadStorageUsage() async {
        storageByteSize = await store.localStorageByteSize()
    }

    private func deleteAllLocalData() {
        Task {
            do {
                try await store.deleteAllLocalData()
                await loadStorageUsage()
                showToast("로컬 데이터를 삭제했습니다.")
            } catch {
                showToast("로컬 데이터를 삭제하지 못했습니다.")
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    toastMessage = nil
                }
            }
        }
    }
}

private struct AppInfoView: View {
    let appVersion: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: YDSpacing.x4) {
                BrandMarkView(size: 64)
                Text("뜨개서랍")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(YDColor.ink)
                Text("버전 \(appVersion)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(YDColor.yarn4)
                Text("라이선스")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(YDColor.ink)
                    .padding(.top, YDSpacing.x2)
                Text("앱 아이콘과 디자인 자산은 뜨개서랍 프로젝트 자산입니다. 외부 오픈소스 패키지는 현재 사용하지 않습니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(YDColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(YDSpacing.x6)
            .background(YDColor.cream0)
            .navigationTitle("앱 정보")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
