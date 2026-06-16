import SwiftUI

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case knitting
    case crochet
    case favorite
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .knitting: "대바늘"
        case .crochet: "코바늘"
        case .favorite: "즐겨찾기"
        case .recent: "최근 열람"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var detailPattern: PatternItem?

    private var filteredPatterns: [PatternItem] {
        store.patterns.filter { pattern in
            let normalizedQuery = query
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedLowercase
            let matchesQuery = normalizedQuery.isEmpty ||
                pattern.searchableText.contains(normalizedQuery)
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .knitting:
                matchesFilter = pattern.craftType == .knitting
            case .crochet:
                matchesFilter = pattern.craftType == .crochet
            case .favorite:
                matchesFilter = pattern.isFavorite
            case .recent:
                matchesFilter = pattern.lastOpenedAt != nil
            }
            return matchesQuery && matchesFilter
        }
        .sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 320), spacing: 13)]
        }
        return [GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("내 도안")
                        .font(YDFont.font(size: 32, weight: .bold))
                        .tracking(-1.1)
                        .foregroundStyle(YDColor.ink)
                    Text("카드를 누르면 마지막 작업 위치로 바로 열립니다.")
                        .font(YDFont.font(size: 14))
                        .foregroundStyle(YDColor.muted)
                }

                searchField

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YDSpacing.x2) {
                        ForEach(LibraryFilter.allCases) { item in
                            filterChip(item)
                        }
                    }
                }

                if filteredPatterns.isEmpty {
                    EmptyLibraryState(
                        isLibraryEmpty: store.patterns.isEmpty,
                        hasQuery: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        filterTitle: filter.title
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 13) {
                        ForEach(filteredPatterns) { pattern in
                            PatternCardView(
                                pattern: pattern,
                                isFileMissing: store.missingFilePatternIDs.contains(pattern.id),
                                hasChecksumMismatch: store.checksumMismatchPatternIDs.contains(pattern.id),
                                onOpen: { store.openPattern(pattern.id) },
                                onToggleFavorite: { store.toggleFavorite(pattern.id) },
                                onShowDetails: { detailPattern = pattern }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 36 : YDSpacing.x4)
            .padding(.vertical, horizontalSizeClass == .regular ? 28 : 22)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $detailPattern) { pattern in
            PatternDetailsView(patternID: pattern.id)
                .environmentObject(store)
        }
    }

    private var searchField: some View {
        HStack(spacing: YDSpacing.x3) {
            YDIconView(icon: .search, size: 20)
                .foregroundStyle(YDColor.muted)
            TextField("도안명, 작가명, 태그 검색", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(YDColor.ink)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 50)
        .background(YDColor.cream0)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(YDColor.line, lineWidth: 1)
        }
        .shadow(color: YDColor.wood3.opacity(0.09), radius: 17, y: 8)
        .accessibilityLabel("도안 검색")
    }

    private func filterChip(_ item: LibraryFilter) -> some View {
        Button {
            filter = item
        } label: {
            Text(item == .all ? "\(item.title) \(store.patterns.count)" : item.title)
                .font(YDFont.font(size: 13, weight: .bold))
                .foregroundStyle(filter == item ? YDColor.cream0 : YDColor.muted)
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .background(filter == item ? YDColor.ink : YDColor.cream0)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(filter == item ? YDColor.ink : YDColor.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == item ? .isSelected : [])
    }
}

private struct EmptyLibraryState: View {
    let isLibraryEmpty: Bool
    let hasQuery: Bool
    let filterTitle: String

    var body: some View {
        VStack(spacing: YDSpacing.x2) {
            YDIconView(icon: isLibraryEmpty ? .library : .search, size: 30)
                .foregroundStyle(YDColor.wood3)
                .padding(.bottom, YDSpacing.x1)
            Text(title)
                .font(YDFont.font(size: 16, weight: .bold))
                .foregroundStyle(YDColor.ink)
            Text(description)
                .font(YDFont.font(size: 13))
                .foregroundStyle(YDColor.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(YDColor.cream0.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: YDRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: YDRadius.medium, style: .continuous)
                .stroke(YDColor.line, style: StrokeStyle(lineWidth: 1, dash: [6]))
        }
    }

    private var title: String {
        if isLibraryEmpty {
            return "보관함이 비어 있습니다."
        }
        return hasQuery ? "검색 결과가 없습니다." : "\(filterTitle) 도안이 없습니다."
    }

    private var description: String {
        if isLibraryEmpty {
            return "상단의 도안 등록 버튼으로 PDF나 이미지를 추가해 주세요."
        }
        return "검색어를 지우거나 다른 필터를 선택해 주세요."
    }
}
