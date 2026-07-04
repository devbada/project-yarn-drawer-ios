import Foundation

actor PatternRepository {
    private let fileManager: FileManager
    private let rootURL: URL
    private let metadataURL: URL
    private let backupURL: URL
    private let hiddenSamplesURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let resolvedRootURL = rootURL ?? applicationSupport.appending(
            path: "YarnDrawer",
            directoryHint: .isDirectory
        )
        self.rootURL = resolvedRootURL
        metadataURL = resolvedRootURL.appending(path: "patterns.json")
        backupURL = resolvedRootURL.appending(path: "patterns.backup.json")
        hiddenSamplesURL = resolvedRootURL.appending(path: "hidden-samples.json")
    }

    func load() throws -> [PatternItem] {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return try loadBackupIfAvailable()
        }

        do {
            return try decode(metadataURL)
        } catch {
            let recoveredPatterns = try loadBackupIfAvailable(originalError: error)
            try write(recoveredPatterns, to: metadataURL)
            return recoveredPatterns
        }
    }

    func save(_ patterns: [PatternItem]) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: metadataURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: metadataURL, to: backupURL)
        }
        try write(patterns.filter { !$0.isSample }, to: metadataURL)
    }

    func saveAfterDeletion(_ patterns: [PatternItem]) throws {
        let persistedPatterns = patterns.filter { !$0.isSample }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try write(persistedPatterns, to: metadataURL)
        try write(persistedPatterns, to: backupURL)
    }

    func hiddenSampleIDs() throws -> Set<PatternItem.ID> {
        guard fileManager.fileExists(atPath: hiddenSamplesURL.path) else {
            return []
        }
        let ids = try decoder.decode(
            [PatternItem.ID].self,
            from: Data(contentsOf: hiddenSamplesURL)
        )
        return Set(ids)
    }

    func hideSample(id: PatternItem.ID) throws {
        var ids = try hiddenSampleIDs()
        ids.insert(id)
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(Array(ids).sorted { $0.uuidString < $1.uuidString })
        try data.write(
            to: hiddenSamplesURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func loadBackupIfAvailable(
        originalError: Error? = nil
    ) throws -> [PatternItem] {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            if let originalError {
                throw originalError
            }
            return []
        }
        return try decode(backupURL)
    }

    private func decode(_ url: URL) throws -> [PatternItem] {
        try decoder.decode(
            [PatternItem].self,
            from: Data(contentsOf: url)
        )
    }

    private func write(_ patterns: [PatternItem], to url: URL) throws {
        let data = try encoder.encode(patterns)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: value)
            }
            let value = try container.decode(String.self)
            if let date = Self.fractionalISO8601Formatter.date(from: value) ??
                Self.iso8601Formatter.date(from: value)
            {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()
}
