import XCTest
@testable import YarnDrawer

final class AnnotationRepositoryTests: XCTestCase {
    func testFreehandHighlightPreservesColorAndStrokeWhenSaved() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let repository = AnnotationRepository(rootURL: rootURL)
        let patternID = UUID()
        let bounds = try XCTUnwrap(
            NormalizedRect(
                rect: CGRect(x: 20, y: 30, width: 120, height: 28),
                in: CGRect(x: 0, y: 0, width: 200, height: 300)
            )
        )
        let annotation = PatternAnnotation(
            id: UUID(),
            type: .highlight,
            pageIndex: 0,
            bounds: bounds,
            highlightColor: nil,
            highlightHex: "80E5D2",
            points: [
                NormalizedPoint(x: 0.1, y: 0.2),
                NormalizedPoint(x: 0.3, y: 0.25),
                NormalizedPoint(x: 0.5, y: 0.3)
            ],
            normalizedLineWidth: 0.04,
            createdAt: Date(timeIntervalSince1970: 1_800)
        )

        try await repository.save([annotation], patternID: patternID)
        let savedAnnotations = try await repository.load(patternID: patternID)

        XCTAssertEqual(savedAnnotations, [annotation])
        XCTAssertEqual(savedAnnotations.first?.resolvedHighlightHex, "80E5D2")
        XCTAssertEqual(savedAnnotations.first?.isFreehandHighlight, true)
    }
}
