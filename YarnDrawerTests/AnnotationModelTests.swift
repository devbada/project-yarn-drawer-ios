import XCTest
@testable import YarnDrawer

final class AnnotationModelTests: XCTestCase {
    func testNormalizedRectRestoresPDFCoordinates() throws {
        let pageBounds = CGRect(x: 10, y: 20, width: 200, height: 400)
        let source = CGRect(x: 60, y: 120, width: 100, height: 80)

        let normalized = try XCTUnwrap(
            NormalizedRect(rect: source, in: pageBounds)
        )
        let restored = normalized.rect(in: pageBounds)

        XCTAssertEqual(restored.origin.x, source.origin.x, accuracy: 0.0001)
        XCTAssertEqual(restored.origin.y, source.origin.y, accuracy: 0.0001)
        XCTAssertEqual(restored.width, source.width, accuracy: 0.0001)
        XCTAssertEqual(restored.height, source.height, accuracy: 0.0001)
    }

    func testNormalizedRectClipsToPageBounds() throws {
        let pageBounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let source = CGRect(x: 80, y: 80, width: 40, height: 40)

        let normalized = try XCTUnwrap(
            NormalizedRect(rect: source, in: pageBounds)
        )

        XCTAssertEqual(normalized.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(normalized.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(normalized.width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(normalized.height, 0.2, accuracy: 0.0001)
    }

    func testLegacyAnnotationUsesYellowHighlight() throws {
        let json = """
        {
          "id": "0A4DCFD8-781F-494D-909B-90A837643528",
          "type": "highlight",
          "pageIndex": 0,
          "bounds": {
            "x": 0.1,
            "y": 0.2,
            "width": 0.3,
            "height": 0.1
          },
          "createdAt": "2026-06-15T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let annotation = try decoder.decode(
            PatternAnnotation.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(annotation.resolvedHighlightColor, .yellow)
        XCTAssertEqual(annotation.resolvedHighlightHex, "F1C878")
        XCTAssertFalse(annotation.isFreehandHighlight)
    }

    func testNormalizedPointRestoresPDFCoordinates() throws {
        let pageBounds = CGRect(x: 10, y: 20, width: 200, height: 400)
        let source = CGPoint(x: 60, y: 120)

        let normalized = try XCTUnwrap(
            NormalizedPoint(point: source, in: pageBounds)
        )
        let restored = normalized.point(in: pageBounds)

        XCTAssertEqual(restored.x, source.x, accuracy: 0.0001)
        XCTAssertEqual(restored.y, source.y, accuracy: 0.0001)
    }

    func testCheckAndCurrentRowAnnotationsRoundTrip() throws {
        let bounds = try XCTUnwrap(
            NormalizedRect(
                rect: CGRect(x: 20, y: 30, width: 40, height: 10),
                in: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )
        let annotations = [
            PatternAnnotation(
                id: UUID(),
                type: .check,
                pageIndex: 1,
                bounds: bounds,
                highlightColor: nil,
                highlightHex: nil,
                points: nil,
                normalizedLineWidth: nil,
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            PatternAnnotation(
                id: UUID(),
                type: .currentRow,
                pageIndex: 2,
                bounds: bounds,
                highlightColor: nil,
                highlightHex: nil,
                points: nil,
                normalizedLineWidth: nil,
                createdAt: Date(timeIntervalSince1970: 2_000)
            )
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            [PatternAnnotation].self,
            from: encoder.encode(annotations)
        )

        XCTAssertEqual(decoded, annotations)
    }

    func testCurrentRowAxisDefaultsToHorizontalAndPersistsVerticalMetadata() throws {
        let bounds = try XCTUnwrap(
            NormalizedRect(
                rect: CGRect(x: 20, y: 0, width: 10, height: 100),
                in: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )
        let legacyCurrentRow = PatternAnnotation(
            id: UUID(),
            type: .currentRow,
            pageIndex: 0,
            bounds: bounds,
            highlightColor: nil,
            highlightHex: nil,
            points: nil,
            normalizedLineWidth: nil,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let verticalCurrentRow = PatternAnnotation(
            id: UUID(),
            type: .currentRow,
            pageIndex: 0,
            bounds: bounds,
            highlightColor: nil,
            highlightHex: nil,
            points: nil,
            normalizedLineWidth: nil,
            createdAt: Date(timeIntervalSince1970: 4_000),
            noteText: PatternAnnotation.currentRowAxisNoteText(.vertical)
        )

        XCTAssertEqual(legacyCurrentRow.currentRowAxis, .horizontal)
        XCTAssertEqual(verticalCurrentRow.currentRowAxis, .vertical)
    }
}
