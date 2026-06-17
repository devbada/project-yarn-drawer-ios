import Foundation

actor SymbolRepository {
    private let fileManager: FileManager
    private let rootURL: URL
    private let symbolsURL: URL

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
        symbolsURL = resolvedRootURL.appending(path: "symbols.json")
    }

    func load() throws -> [KnitSymbol] {
        guard fileManager.fileExists(atPath: symbolsURL.path) else {
            return []
        }
        return try decoder.decode(
            [KnitSymbol].self,
            from: Data(contentsOf: symbolsURL)
        )
    }

    func save(_ symbols: [KnitSymbol]) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let userSymbols = symbols.filter { !$0.isSystem }
        let data = try encoder.encode(userSymbols)
        try data.write(
            to: symbolsURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func delete(patternID: PatternItem.ID) throws {
        let remainingSymbols = try load().filter { $0.patternID != patternID }
        try save(remainingSymbols)
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
