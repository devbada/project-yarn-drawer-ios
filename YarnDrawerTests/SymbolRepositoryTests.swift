import XCTest
@testable import YarnDrawer

final class SymbolRepositoryTests: XCTestCase {
    func testSymbolsRoundTripExcludesSystemDefaults() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = SymbolRepository(rootURL: rootURL)
        let userSymbol = KnitSymbol(
            id: UUID(),
            scope: .common,
            patternID: nil,
            glyph: "K",
            drawingStrokes: nil,
            name: "겉뜨기",
            abbreviation: "k",
            description: "knit",
            linkURLString: "https://example.com/k",
            isFavorite: true,
            isSystem: false,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await repository.save(KnitSymbol.defaultCommonSymbols + [userSymbol])
        let loadedSymbols = try await repository.load()

        XCTAssertEqual(loadedSymbols, [userSymbol])
    }

    func testDeletesSymbolsForPattern() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = SymbolRepository(rootURL: rootURL)
        let patternID = UUID()
        let patternSymbol = KnitSymbol(
            id: UUID(),
            scope: .pattern,
            patternID: patternID,
            glyph: "V",
            drawingStrokes: nil,
            name: "중앙 늘리기",
            abbreviation: "m1",
            description: "도안 전용",
            linkURLString: nil,
            isFavorite: false,
            isSystem: false,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await repository.save([patternSymbol])
        try await repository.delete(patternID: patternID)

        let loadedSymbols = try await repository.load()
        XCTAssertTrue(loadedSymbols.isEmpty)
    }
}
