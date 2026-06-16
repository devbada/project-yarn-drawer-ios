import XCTest
@testable import YarnDrawer

final class PatternRepositoryTests: XCTestCase {
    func testRecoversMetadataFromBackup() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = PatternRepository(rootURL: rootURL)
        let pattern = PatternItem.samples[0].asPersistedTestPattern

        try await repository.save([pattern])
        try await repository.save([pattern])

        let metadataURL = rootURL.appending(path: "patterns.json")
        try Data("invalid-json".utf8).write(to: metadataURL, options: .atomic)

        let recovered = try await repository.load()

        XCTAssertEqual(recovered, [pattern])
    }

    func testDeletionUpdatesMetadataAndBackup() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = PatternRepository(rootURL: rootURL)
        let pattern = PatternItem.samples[0].asPersistedTestPattern

        try await repository.save([pattern])
        try await repository.saveAfterDeletion([])

        let metadataURL = rootURL.appending(path: "patterns.json")
        try Data("invalid-json".utf8).write(to: metadataURL, options: .atomic)

        let recovered = try await repository.load()

        XCTAssertTrue(recovered.isEmpty)
    }

    func testHiddenSampleIDsRoundTrip() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = PatternRepository(rootURL: rootURL)
        let sampleID = PatternItem.samples[0].id

        try await repository.hideSample(id: sampleID)
        let hiddenSampleIDs = try await repository.hiddenSampleIDs()

        XCTAssertEqual(hiddenSampleIDs, Set([sampleID]))
    }
}

private extension PatternItem {
    var asPersistedTestPattern: PatternItem {
        var copy = self
        copy.isSample = false
        return copy
    }
}
