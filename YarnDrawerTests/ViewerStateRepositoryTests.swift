import XCTest
@testable import YarnDrawer

final class ViewerStateRepositoryTests: XCTestCase {
    func testSavesAndLoadsLastPage() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = ViewerStateRepository(rootURL: rootURL)
        let state = PatternViewerState(
            patternID: UUID(),
            lastPageIndex: 4,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        try await repository.save(state)
        let loaded = try await repository.load(patternID: state.patternID)

        XCTAssertEqual(loaded, state)
    }
}
