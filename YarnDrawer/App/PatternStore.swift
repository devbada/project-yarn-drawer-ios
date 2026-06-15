import Foundation

enum PatternStoreError: LocalizedError {
    case patternNotFound
    case sampleIsReadOnly
    case invalidTitle
    case invalidDesignerName

    var errorDescription: String? {
        switch self {
        case .patternNotFound:
            "도안 정보를 찾지 못했습니다."
        case .sampleIsReadOnly:
            "샘플 도안은 수정하거나 삭제할 수 없습니다."
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
            patterns = PatternItem.samples + persistedPatterns
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
            let pattern = try await fileAssetStore.importPattern(draft)
            patterns.append(pattern)
            try await persist()
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

    func updatePattern(_ pattern: PatternItem) async throws {
        guard let index = patterns.firstIndex(where: { $0.id == pattern.id }) else {
            throw PatternStoreError.patternNotFound
        }
        guard !patterns[index].isSample else {
            throw PatternStoreError.sampleIsReadOnly
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

    func deletePattern(_ id: PatternItem.ID) async throws {
        guard let pattern = pattern(id: id) else {
            throw PatternStoreError.patternNotFound
        }
        guard !pattern.isSample else {
            throw PatternStoreError.sampleIsReadOnly
        }

        let remainingPatterns = patterns.filter { $0.id != id }
        try await repository.saveAfterDeletion(remainingPatterns)
        patterns = remainingPatterns

        if selectedPattern?.id == id {
            selectedPattern = nil
        }

        try? await fileAssetStore.deletePatternFiles(patternID: id)
        try? await annotationRepository.delete(patternID: id)
        try? await viewerStateRepository.delete(patternID: id)
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

    func saveViewerPage(_ pageIndex: Int, for patternID: PatternItem.ID) async throws {
        let state = PatternViewerState(
            patternID: patternID,
            lastPageIndex: max(0, pageIndex),
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
}
