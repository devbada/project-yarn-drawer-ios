import Foundation

enum PatternStoreError: LocalizedError {
    case patternNotFound
    case sampleEditNotAllowed
    case invalidTitle
    case invalidDesignerName

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
        }
    }
}

@MainActor
final class PatternStore: ObservableObject {
    @Published private(set) var patterns: [PatternItem] = PatternItem.samples
    @Published private(set) var missingFilePatternIDs: Set<PatternItem.ID> = []
    @Published private(set) var checksumMismatchPatternIDs: Set<PatternItem.ID> = []
    @Published var selectedPattern: PatternItem?
    @Published var isImporting = false
    @Published var importErrorMessage: String?

    private let repository: PatternRepository
    private let fileAssetStore: FileAssetStore
    private let annotationRepository: AnnotationRepository
    private let viewerStateRepository: ViewerStateRepository

    init(
        repository: PatternRepository = PatternRepository(),
        fileAssetStore: FileAssetStore = FileAssetStore(),
        annotationRepository: AnnotationRepository = AnnotationRepository(),
        viewerStateRepository: ViewerStateRepository = ViewerStateRepository()
    ) {
        self.repository = repository
        self.fileAssetStore = fileAssetStore
        self.annotationRepository = annotationRepository
        self.viewerStateRepository = viewerStateRepository
    }

    func load() async {
        do {
            let persistedPatterns = try await repository.load()
            let hiddenSampleIDs = (try? await repository.hiddenSampleIDs()) ?? []
            let visibleSamples = PatternItem.samples.filter {
                !hiddenSampleIDs.contains($0.id)
            }
            patterns = visibleSamples + persistedPatterns
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

    func annotations(for patternID: PatternItem.ID) async throws -> [PatternAnnotation] {
        try await annotationRepository.load(patternID: patternID)
    }

    func addAnnotation(
        _ annotation: PatternAnnotation,
        to patternID: PatternItem.ID
    ) async throws {
        try await annotationRepository.append(annotation, patternID: patternID)
    }

    func saveAnnotations(
        _ annotations: [PatternAnnotation],
        for patternID: PatternItem.ID
    ) async throws {
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

    private func refreshMissingFileStatus() async {
        missingFilePatternIDs = await fileAssetStore.missingFilePatternIDs(for: patterns)
        checksumMismatchPatternIDs = await fileAssetStore.checksumMismatchPatternIDs(for: patterns)
    }
}
