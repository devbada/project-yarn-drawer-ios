import SwiftUI

private struct KnitSymbol: Identifiable {
    let id = UUID()
    let glyph: String
    let name: String
    let metadata: String
}

struct SymbolsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var query = ""
    @State private var toastMessage: String?

    private let symbols = [
        KnitSymbol(glyph: "○", name: "바늘비우기", metadata: "yo · yarn over"),
        KnitSymbol(glyph: "＼", name: "왼 코 늘리기", metadata: "m1l · 왼쪽 기울임"),
        KnitSymbol(glyph: "DS", name: "더블 스티치", metadata: "German short row")
    ]

    private var filteredSymbols: [KnitSymbol] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return symbols }
        return symbols.filter {
            "\($0.name) \($0.metadata)".localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("기호")
                                .font(.system(size: 32, weight: .bold))
                                .tracking(-1.1)
                                .foregroundStyle(YDColor.ink)
                            Text("공통 기호를 관리합니다. 도안 전용 기호는 뷰어에서 등록합니다.")
                                .font(.system(size: 14))
                                .foregroundStyle(YDColor.muted)
                        }
                        Spacer()
                        YDIconButton(
                            icon: .plus,
                            accessibilityLabel: "새 기호 등록"
                        ) {
                            showToast("기호 등록 화면은 다음 구현 묶음에서 연결합니다.")
                        }
                    }

                    HStack(spacing: YDSpacing.x3) {
                        YDIconView(icon: .search, size: 20)
                            .foregroundStyle(YDColor.muted)
                        TextField("기호명, 약어 검색", text: $query)
                    }
                    .padding(.horizontal, 15)
                    .frame(minHeight: 50)
                    .background(YDColor.cream0)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(YDColor.line, lineWidth: 1)
                    }

                    LazyVGrid(
                        columns: horizontalSizeClass == .regular
                            ? [GridItem(.adaptive(minimum: 300), spacing: 10)]
                            : [GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(filteredSymbols) { symbol in
                            symbolCard(symbol)
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
    }

    private func symbolCard(_ symbol: KnitSymbol) -> some View {
        HStack(spacing: YDSpacing.x3) {
            Text(symbol.glyph)
                .font(.system(size: 23, weight: .black))
                .foregroundStyle(YDColor.yarn4)
                .frame(width: 58, height: 58)
                .background(YDColor.surfaceGreen)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                Text(symbol.metadata)
                    .font(.system(size: 12))
                    .foregroundStyle(YDColor.muted)
            }
            Spacer()
            Button("링크") {
                showToast("외부 링크 목적지 확인 후 시스템 브라우저에서 엽니다.")
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(YDColor.wood3)
            .frame(minWidth: 44, minHeight: 38)
            .padding(.horizontal, 8)
            .background(YDColor.cream0)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(YDColor.line, lineWidth: 1)
            }
        }
        .padding(11)
        .ydSurfaceCard()
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

