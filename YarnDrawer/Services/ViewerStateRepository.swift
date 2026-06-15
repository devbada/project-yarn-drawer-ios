import Foundation

actor ViewerStateRepository {
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.rootURL = rootURL ?? applicationSupport
            .appending(path: "YarnDrawer", directoryHint: .isDirectory)
            .appending(path: "viewer-states", directoryHint: .isDirectory)
    }

    func load(patternID: UUID) throws -> PatternViewerState? {
        let url = fileURL(for: patternID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(
            PatternViewerState.self,
            from: Data(contentsOf: url)
        )
    }

    func save(_ state: PatternViewerState) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(state)
        try data.write(
            to: fileURL(for: state.patternID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
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
