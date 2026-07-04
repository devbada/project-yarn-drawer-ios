import Foundation

enum PatternStoreError: LocalizedError {
    case patternNotFound
    case sampleEditNotAllowed
    case invalidTitle
    case invalidDesignerName
    case invalidSymbolGlyph
    case invalidSymbolName
    case invalidSymbolLink
    case systemSymbolEditNotAllowed
    #if DEBUG
    case forcedTestSaveFailure
    #endif

    var errorDescription: String? {
        switch self {
        case .patternNotFound:
            "도안 정보를 찾지 못했습니다."
        case .sampleEditNotAllowed:
            "샘플 도안은 수정할 수 없습니다."
        case .invalidTitle:
            "도안명은 1자 이상 100자 이하로 입력해 주세요."
        case .invalidDesignerName:
            "작가명은 100자 이하로 입력해 주세요."
        case .invalidSymbolGlyph:
            "기호를 canvas에 그려 주세요."
        case .invalidSymbolName:
            "기호 이름은 1자 이상 60자 이하로 입력해 주세요."
        case .invalidSymbolLink:
            "외부 링크는 https 주소로 입력해 주세요."
        case .systemSymbolEditNotAllowed:
            "기본 기호는 삭제할 수 없습니다."
        #if DEBUG
        case .forcedTestSaveFailure:
            "테스트용으로 강제된 저장 실패입니다."
        #endif
        }
    }
}

@MainActor
final class PatternStore: ObservableObject {
    @Published private(set) var patterns: [PatternItem] = PatternItem.samples
    @Published private(set) var symbols: [KnitSymbol] = KnitSymbol.defaultCommonSymbols
    @Published private(set) var missingFilePatternIDs: Set<PatternItem.ID> = []
    @Published private(set) var checksumMismatchPatternIDs: Set<PatternItem.ID> = []
    @Published var selectedPattern: PatternItem?
    @Published var isImporting = false
    @Published var importErrorMessage: String?

    private let repository: PatternRepository
    private let fileAssetStore: FileAssetStore
    private let annotationRepository: AnnotationRepository
    private let viewerStateRepository: ViewerStateRepository
    private let symbolRepository: SymbolRepository

    init(
        repository: PatternRepository = PatternRepository(),
        fileAssetStore: FileAssetStore = FileAssetStore(),
        annotationRepository: AnnotationRepository = AnnotationRepository(),
        viewerStateRepository: ViewerStateRepository = ViewerStateRepository(),
        symbolRepository: SymbolRepository = SymbolRepository()
    ) {
        self.repository = repository
        self.fileAssetStore = fileAssetStore
        self.annotationRepository = annotationRepository
        self.viewerStateRepository = viewerStateRepository
        self.symbolRepository = symbolRepository
    }

    func load() async {
        do {
            let persistedPatterns = try await repository.load()
            let persistedSymbols = try await symbolRepository.load()
            let hiddenSampleIDs = (try? await repository.hiddenSampleIDs()) ?? []
            let visibleSamples = PatternItem.samples.filter {
                !hiddenSampleIDs.contains($0.id)
            }
            patterns = visibleSamples + persistedPatterns
            symbols = KnitSymbol.defaultCommonSymbols + persistedSymbols
            await refreshMissingFileStatus()
        } catch {
            importErrorMessage = "저장된 도안 정보를 불러오지 못했습니다."
        }
    }

    func importPattern(_ draft: PatternImportDraft) async -> Bool {
        guard validate(draft) else {
            return false
        }

        isImporting = true
        importErrorMessage = nil
        defer { isImporting = false }

        do {
            var pattern = try await fileAssetStore.importPattern(draft)
            pattern.lastOpenedAt = Date()
            patterns.append(pattern)
            try await persist()
            await refreshMissingFileStatus()
            selectedPattern = pattern
            return true
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "도안을 등록하지 못했습니다."
            return false
        }
    }

    func toggleFavorite(_ id: PatternItem.ID) {
        guard let index = patterns.firstIndex(where: { $0.id == id }) else {
            return
        }
        patterns[index].isFavorite.toggle()
        patterns[index].updatedAt = Date()
        Task {
            try? await persist()
        }
    }

    func pattern(id: PatternItem.ID) -> PatternItem? {
        patterns.first { $0.id == id }
    }

    func openPattern(_ id: PatternItem.ID) {
        guard let index = patterns.firstIndex(where: { $0.id == id }) else {
            return
        }
        patterns[index].lastOpenedAt = Date()
        patterns[index].updatedAt = Date()
        selectedPattern = patterns[index]

        guard !patterns[index].isSample else {
            return
        }
        Task {
            try? await persist()
        }
    }

    func updatePattern(_ pattern: PatternItem) async throws {
        guard let index = patterns.firstIndex(where: { $0.id == pattern.id }) else {
            throw PatternStoreError.patternNotFound
        }
        guard !patterns[index].isSample else {
            throw PatternStoreError.sampleEditNotAllowed
        }

        let title = pattern.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100 else {
            throw PatternStoreError.invalidTitle
        }
        guard (pattern.designerName ?? "").count <= 100 else {
            throw PatternStoreError.invalidDesignerName
        }

        var updatedPattern = pattern
        updatedPattern.title = title
        updatedPattern.updatedAt = Date()

        var updatedPatterns = patterns
        updatedPatterns[index] = updatedPattern
        try await repository.save(updatedPatterns)
        patterns = updatedPatterns

        if selectedPattern?.id == updatedPattern.id {
            selectedPattern = updatedPattern
        }
    }

    func updateProgress(_ progress: Double, for id: PatternItem.ID) async throws {
        guard let index = patterns.firstIndex(where: { $0.id == id }) else {
            throw PatternStoreError.patternNotFound
        }
        guard !patterns[index].isSample else {
            return
        }

        patterns[index].progress = min(max(progress, 0), 1)
        patterns[index].updatedAt = Date()
        try await persist()

        if selectedPattern?.id == id {
            selectedPattern = patterns[index]
        }
    }

    func deletePattern(_ id: PatternItem.ID) async throws {
        guard let pattern = pattern(id: id) else {
            throw PatternStoreError.patternNotFound
        }

        if pattern.isSample {
            try await repository.hideSample(id: id)
            patterns.removeAll { $0.id == id }
            await refreshMissingFileStatus()
            if selectedPattern?.id == id {
                selectedPattern = nil
            }
            try? await annotationRepository.delete(patternID: id)
            try? await viewerStateRepository.delete(patternID: id)
            try? await symbolRepository.delete(patternID: id)
            return
        }

        let remainingPatterns = patterns.filter { $0.id != id }
        try await repository.saveAfterDeletion(remainingPatterns)
        patterns = remainingPatterns
        await refreshMissingFileStatus()

        if selectedPattern?.id == id {
            selectedPattern = nil
        }

        try? await fileAssetStore.deletePatternFiles(patternID: id)
        try? await annotationRepository.delete(patternID: id)
        try? await viewerStateRepository.delete(patternID: id)
        try? await symbolRepository.delete(patternID: id)
    }

    func reconnectPatternFile(
        sourceURL: URL,
        for id: PatternItem.ID
    ) async throws {
        guard let index = patterns.firstIndex(where: { $0.id == id }) else {
            throw PatternStoreError.patternNotFound
        }
        guard !patterns[index].isSample else {
            throw PatternStoreError.sampleEditNotAllowed
        }

        let updatedPattern = try await fileAssetStore.reconnectPatternFile(
            sourceURL: sourceURL,
            for: patterns[index]
        )
        patterns[index] = updatedPattern
        try await persist()
        await refreshMissingFileStatus()

        if selectedPattern?.id == id {
            selectedPattern = updatedPattern
        }
    }

    func localStorageByteSize() async -> Int64 {
        await fileAssetStore.appDataByteSize()
    }

    func deleteAllLocalData() async throws {
        try await fileAssetStore.deleteAllAppData()
        patterns = PatternItem.samples
        symbols = KnitSymbol.defaultCommonSymbols
        missingFilePatternIDs = []
        checksumMismatchPatternIDs = []
        selectedPattern = nil
        importErrorMessage = nil
    }

    func viewURL(for pattern: PatternItem) async -> URL? {
        guard let asset = pattern.viewAsset else {
            return nil
        }
        return await fileAssetStore.fileURL(for: asset, patternID: pattern.id)
    }

    func thumbnailURL(for pattern: PatternItem) async -> URL? {
        await fileAssetStore.thumbnailURL(for: pattern)
    }

    func annotations(for patternID: PatternItem.ID) async throws -> [PatternAnnotation] {
        try await annotationRepository.load(patternID: patternID)
    }

    func addAnnotation(
        _ annotation: PatternAnnotation,
        to patternID: PatternItem.ID
    ) async throws {
        #if DEBUG
        try Self.consumeForcedSaveFailureIfNeeded()
        #endif
        try await annotationRepository.append(annotation, patternID: patternID)
    }

    func saveAnnotations(
        _ annotations: [PatternAnnotation],
        for patternID: PatternItem.ID
    ) async throws {
        #if DEBUG
        try Self.consumeForcedSaveFailureIfNeeded()
        #endif
        try await annotationRepository.save(annotations, patternID: patternID)
    }

    func viewerState(for patternID: PatternItem.ID) async throws -> PatternViewerState? {
        try await viewerStateRepository.load(patternID: patternID)
    }

    func saveViewerState(
        pageIndex: Int,
        scaleFactor: Double?,
        for patternID: PatternItem.ID
    ) async throws {
        let state = PatternViewerState(
            patternID: patternID,
            lastPageIndex: max(0, pageIndex),
            scaleFactor: scaleFactor.map { min(max($0, 0.25), 8) },
            updatedAt: Date()
        )
        try await viewerStateRepository.save(state)
    }

    func commonSymbols(matching query: String = "", favoritesOnly: Bool = false) -> [KnitSymbol] {
        symbols
            .filter { symbol in
                symbol.scope == .common &&
                    (!favoritesOnly || symbol.isFavorite) &&
                    symbol.matches(query)
            }
            .sorted(by: sortSymbols)
    }

    /// 뷰어 floating 패널 전용 목록. 도안 전용 기호는 항상 전부 노출하지만, 공통 기호는
    /// 즐겨찾기한 것만 보여준다(작업 중 참고용이라 전체 공통 기호를 늘어놓으면 오히려
    /// 찾기 어렵다는 화면 명세 기준).
    func symbols(
        for patternID: PatternItem.ID,
        matching query: String = ""
    ) -> [KnitSymbol] {
        symbols
            .filter { symbol in
                let matchesScope = (symbol.scope == .common && symbol.isFavorite) ||
                    symbol.patternID == patternID
                return matchesScope && symbol.matches(query)
            }
            .sorted(by: sortSymbols)
    }

    func saveSymbol(_ draft: KnitSymbolDraft) async throws {
        let symbol = try normalizedSymbol(from: draft)
        if let index = symbols.firstIndex(where: { $0.id == symbol.id }) {
            guard !symbols[index].isSystem else {
                throw PatternStoreError.systemSymbolEditNotAllowed
            }
            symbols[index] = symbol
        } else {
            symbols.append(symbol)
        }
        try await symbolRepository.save(symbols)
    }

    func deleteSymbol(_ id: KnitSymbol.ID) async throws {
        guard let symbol = symbols.first(where: { $0.id == id }) else {
            throw PatternStoreError.patternNotFound
        }
        guard !symbol.isSystem else {
            throw PatternStoreError.systemSymbolEditNotAllowed
        }
        symbols.removeAll { $0.id == id }
        try await symbolRepository.save(symbols)
    }

    private func validate(_ draft: PatternImportDraft) -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100 else {
            importErrorMessage = "도안명은 1자 이상 100자 이하로 입력해 주세요."
            return false
        }
        guard draft.designerName.count <= 100 else {
            importErrorMessage = "작가명은 100자 이하로 입력해 주세요."
            return false
        }
        return true
    }

    private func persist() async throws {
        try await repository.save(patterns)
    }

    private func normalizedSymbol(from draft: KnitSymbolDraft) throws -> KnitSymbol {
        let glyph = "그림"
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviation = draft.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkURLString = draft.linkURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !draft.drawingStrokes.isEmpty else {
            throw PatternStoreError.invalidSymbolGlyph
        }
        guard !name.isEmpty, name.count <= 60 else {
            throw PatternStoreError.invalidSymbolName
        }
        if !linkURLString.isEmpty {
            guard
                let url = URL(string: linkURLString),
                url.scheme == "https",
                url.host() != nil || url.host != nil
            else {
                throw PatternStoreError.invalidSymbolLink
            }
        }

        let existingSymbol = draft.id.flatMap { id in
            symbols.first { $0.id == id }
        }
        let now = Date()
        return KnitSymbol(
            id: draft.id ?? UUID(),
            scope: draft.scope,
            patternID: draft.scope == .pattern ? draft.patternID : nil,
            glyph: glyph,
            drawingStrokes: draft.drawingStrokes.isEmpty ? nil : draft.drawingStrokes,
            name: name,
            abbreviation: abbreviation,
            description: description,
            linkURLString: linkURLString.isEmpty ? nil : linkURLString,
            isFavorite: draft.isFavorite,
            isSystem: existingSymbol?.isSystem ?? false,
            createdAt: existingSymbol?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func sortSymbols(_ lhs: KnitSymbol, _ rhs: KnitSymbol) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }
        if lhs.scope != rhs.scope {
            return lhs.scope == .pattern
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func refreshMissingFileStatus() async {
        missingFilePatternIDs = await fileAssetStore.missingFilePatternIDs(for: patterns)
        checksumMismatchPatternIDs = await fileAssetStore.checksumMismatchPatternIDs(for: patterns)
    }

    #if DEBUG
    /// UI 테스트가 저장 실패 → 재시도 흐름을 결정론적으로 검증할 수 있도록,
    /// `YARN_DRAWER_UI_TEST_FORCE_SAVE_FAILURE_COUNT`로 지정한 횟수만큼만
    /// annotation 저장을 강제로 실패시킨다. 0이면(기본값, 일반 빌드 포함) 아무 영향이 없다.
    private static var forcedSaveFailuresRemaining: Int = {
        Int(ProcessInfo.processInfo.environment["YARN_DRAWER_UI_TEST_FORCE_SAVE_FAILURE_COUNT"] ?? "") ?? 0
    }()

    private static func consumeForcedSaveFailureIfNeeded() throws {
        guard forcedSaveFailuresRemaining > 0 else {
            return
        }
        forcedSaveFailuresRemaining -= 1
        throw PatternStoreError.forcedTestSaveFailure
    }
    #endif
}
