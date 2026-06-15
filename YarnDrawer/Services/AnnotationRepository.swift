import Foundation

actor AnnotationRepository {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        rootURL = applicationSupport
            .appending(path: "YarnDrawer", directoryHint: .isDirectory)
            .appending(path: "annotations", directoryHint: .isDirectory)
    }

    func load(patternID: UUID) throws -> [PatternAnnotation] {
        let fileURL = fileURL(for: patternID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try decoder.decode(
            [PatternAnnotation].self,
            from: Data(contentsOf: fileURL)
        )
    }

    func append(_ annotation: PatternAnnotation, patternID: UUID) throws {
        var annotations = try load(patternID: patternID)
        guard !annotations.contains(where: { $0.id == annotation.id }) else {
            return
        }
        annotations.append(annotation)
        try save(annotations, patternID: patternID)
    }

    func save(_ annotations: [PatternAnnotation], patternID: UUID) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(annotations)
        try data.write(to: fileURL(for: patternID), options: .atomic)
    }

    func delete(patternID: UUID) throws {
        let url = fileURL(for: patternID)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for patternID: UUID) -> URL {
        rootURL.appending(path: "\(patternID.uuidString.lowercased()).json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
