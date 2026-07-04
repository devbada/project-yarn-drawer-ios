import UIKit
import XCTest
@testable import YarnDrawer

final class FileAssetStoreTests: XCTestCase {
    func testPDFImportCreatesOriginalAssetChecksumPageCountAndThumbnail() async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pdfURL = try makeTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pattern = try await store.importPattern(
            makeDraft(sourceURL: pdfURL, title: "PDF 테스트")
        )

        XCTAssertEqual(pattern.sourceFileType, .pdf)
        XCTAssertEqual(pattern.pageCount, 1)
        let originalAsset = try XCTUnwrap(pattern.originalAsset)
        let viewAsset = try XCTUnwrap(pattern.viewAsset)
        XCTAssertEqual(originalAsset.id, viewAsset.id, "PDF는 원본이 곧 작업용 문서다")
        XCTAssertFalse(originalAsset.checksumSHA256.isEmpty)

        let loadedThumbnailURL = await store.thumbnailURL(for: pattern)
        let thumbnailURL = try XCTUnwrap(loadedThumbnailURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    func testJPGImageImportPreservesOriginalAndConvertsToWorkingPDF() async throws {
        try await assertImageImportPreservesOriginalAndConvertsToWorkingPDF(
            extension: "jpg",
            expectedSourceType: .jpg
        )
    }

    func testJPEGImageImportPreservesOriginalAndConvertsToWorkingPDF() async throws {
        try await assertImageImportPreservesOriginalAndConvertsToWorkingPDF(
            extension: "jpeg",
            expectedSourceType: .jpeg
        )
    }

    func testPNGImageImportPreservesOriginalAndConvertsToWorkingPDF() async throws {
        try await assertImageImportPreservesOriginalAndConvertsToWorkingPDF(
            extension: "png",
            expectedSourceType: .png
        )
    }

    private func assertImageImportPreservesOriginalAndConvertsToWorkingPDF(
        extension fileExtension: String,
        expectedSourceType: SourceFileType
    ) async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let imageURL = try makeTestImage(extension: fileExtension)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let pattern = try await store.importPattern(
            makeDraft(sourceURL: imageURL, title: "이미지 테스트", craftType: .crochet)
        )

        XCTAssertEqual(pattern.sourceFileType, expectedSourceType)
        XCTAssertEqual(pattern.pageCount, 1)
        let originalAsset = try XCTUnwrap(pattern.originalAsset)
        let viewAsset = try XCTUnwrap(pattern.viewAsset)
        XCTAssertNotEqual(originalAsset.id, viewAsset.id, "이미지는 원본과 변환 PDF가 별개 파일이어야 한다")
        XCTAssertEqual(viewAsset.mimeType, "application/pdf")

        let originalURL = await store.fileURL(for: originalAsset, patternID: pattern.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        let viewURL = await store.fileURL(for: viewAsset, patternID: pattern.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: viewURL.path))

        let loadedThumbnailURL = await store.thumbnailURL(for: pattern)
        let thumbnailURL = try XCTUnwrap(loadedThumbnailURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    func testReconnectUpdatesAssetsButPreservesPatternIDForAnnotationsAndViewerState() async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pdfURL = try makeTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pattern = try await store.importPattern(
            makeDraft(sourceURL: pdfURL, title: "재연결 테스트")
        )

        // annotation/viewerState는 FileAssetStore가 아니라 patternID로 keyed된 별도
        // 저장소가 관리한다. reconnect가 patternID를 바꾸지 않아야 기존 표시가 유지된다.
        let annotationRepository = AnnotationRepository(
            rootURL: rootURL.appending(path: "annotations", directoryHint: .isDirectory)
        )
        let bounds = try XCTUnwrap(
            NormalizedRect(
                rect: CGRect(x: 10, y: 10, width: 20, height: 20),
                in: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )
        let annotation = PatternAnnotation(
            id: UUID(),
            type: .check,
            pageIndex: 0,
            bounds: bounds,
            highlightColor: nil,
            highlightHex: nil,
            points: nil,
            normalizedLineWidth: nil,
            createdAt: Date(timeIntervalSince1970: 1_800)
        )
        try await annotationRepository.append(annotation, patternID: pattern.id)

        let viewerStateRepository = ViewerStateRepository(
            rootURL: rootURL.appending(path: "viewer-state", directoryHint: .isDirectory)
        )
        let viewerState = PatternViewerState(
            patternID: pattern.id,
            lastPageIndex: 3,
            scaleFactor: 1.5,
            updatedAt: Date(timeIntervalSince1970: 2_400)
        )
        try await viewerStateRepository.save(viewerState)

        let newPDFURL = try makeTestPDF(pageCount: 2)
        defer { try? FileManager.default.removeItem(at: newPDFURL) }
        let reconnected = try await store.reconnectPatternFile(sourceURL: newPDFURL, for: pattern)

        XCTAssertEqual(reconnected.id, pattern.id, "재연결은 같은 patternID를 유지해야 한다")
        XCTAssertEqual(reconnected.pageCount, 2)
        XCTAssertNotEqual(
            reconnected.originalAsset?.checksumSHA256,
            pattern.originalAsset?.checksumSHA256
        )

        let preservedAnnotations = try await annotationRepository.load(patternID: reconnected.id)
        XCTAssertEqual(preservedAnnotations, [annotation])
        let loadedViewerState = try await viewerStateRepository.load(patternID: reconnected.id)
        let preservedViewerState = try XCTUnwrap(loadedViewerState)
        XCTAssertEqual(preservedViewerState, viewerState)
    }

    func testReconnectFailureLeavesExistingFilesIntact() async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pdfURL = try makeTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pattern = try await store.importPattern(
            makeDraft(sourceURL: pdfURL, title: "재연결 실패 테스트")
        )
        let originalURL = await store.fileURL(
            for: try XCTUnwrap(pattern.originalAsset),
            patternID: pattern.id
        )
        let originalChecksum = try Data(contentsOf: originalURL)

        let corruptURL = FileManager.default.temporaryDirectory
            .appending(path: "corrupt-\(UUID().uuidString).pdf")
        try Data("이것은 유효한 PDF가 아닙니다".utf8).write(to: corruptURL)
        defer { try? FileManager.default.removeItem(at: corruptURL) }

        do {
            _ = try await store.reconnectPatternFile(sourceURL: corruptURL, for: pattern)
            XCTFail("손상된 PDF로의 재연결은 실패해야 한다")
        } catch {
            // 실패를 기대한다.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertEqual(try Data(contentsOf: originalURL), originalChecksum, "실패 시 기존 파일이 손상되면 안 된다")
    }

    func testChecksumMismatchDetectedWhenFileContentsChange() async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pdfURL = try makeTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pattern = try await store.importPattern(
            makeDraft(sourceURL: pdfURL, title: "체크섬 테스트")
        )

        let assetURL = await store.fileURL(
            for: try XCTUnwrap(pattern.originalAsset),
            patternID: pattern.id
        )
        try Data("변조된 내용".utf8).write(to: assetURL, options: .atomic)

        let mismatched = await store.checksumMismatchPatternIDs(for: [pattern])
        XCTAssertEqual(mismatched, Set([pattern.id]))
        let missing = await store.missingFilePatternIDs(for: [pattern])
        XCTAssertTrue(missing.isEmpty, "내용만 바뀐 경우는 누락이 아니라 mismatch여야 한다")
    }

    func testMissingFileDetectedWhenAssetDeleted() async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pdfURL = try makeTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pattern = try await store.importPattern(
            makeDraft(sourceURL: pdfURL, title: "누락 테스트")
        )

        let assetURL = await store.fileURL(
            for: try XCTUnwrap(pattern.originalAsset),
            patternID: pattern.id
        )
        try FileManager.default.removeItem(at: assetURL)

        let missing = await store.missingFilePatternIDs(for: [pattern])
        XCTAssertEqual(missing, Set([pattern.id]))
    }

    func testDeletePatternFilesRemovesPatternDirectory() async throws {
        let (store, rootURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pdfURL = try makeTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pattern = try await store.importPattern(
            makeDraft(sourceURL: pdfURL, title: "삭제 테스트")
        )
        let originalURL = await store.fileURL(
            for: try XCTUnwrap(pattern.originalAsset),
            patternID: pattern.id
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        try await store.deletePatternFiles(patternID: pattern.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    // MARK: - Fixtures

    private func makeStore() -> (FileAssetStore, URL) {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return (FileAssetStore(rootURL: rootURL), rootURL)
    }

    private func makeDraft(
        sourceURL: URL,
        title: String,
        craftType: CraftType = .knitting
    ) -> PatternImportDraft {
        PatternImportDraft(
            sourceURL: sourceURL,
            title: title,
            designerName: "",
            craftType: craftType,
            tagsText: ""
        )
    }

    private func makeTestPDF(pageCount: Int = 1) throws -> URL {
        let pageBounds = CGRect(x: 0, y: 0, width: 200, height: 300)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "fileassetstore-test-\(UUID().uuidString).pdf")
        try renderer.writePDF(to: url) { context in
            for _ in 0..<max(1, pageCount) {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(pageBounds)
            }
        }
        return url
    }

    private func makeTestImage(extension fileExtension: String) throws -> URL {
        let size = CGSize(width: 120, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "fileassetstore-test-\(UUID().uuidString).\(fileExtension)")
        let data: Data? = fileExtension == "png"
            ? image.pngData()
            : image.jpegData(compressionQuality: 0.9)
        try XCTUnwrap(data).write(to: url)
        return url
    }
}
