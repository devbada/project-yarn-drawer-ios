import XCTest
@testable import YarnDrawer

@MainActor
final class PatternStoreTests: XCTestCase {
    func testPatternScopedSymbolIsIsolatedByPatternID() async throws {
        let (store, rootURL) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let patternA = UUID()
        let patternB = UUID()
        try await store.saveSymbol(makeDraft(scope: .pattern, patternID: patternA, name: "패턴 A 전용 기호"))

        let symbolsForA = store.symbols(for: patternA)
        let symbolsForB = store.symbols(for: patternB)

        XCTAssertTrue(symbolsForA.contains { $0.name == "패턴 A 전용 기호" })
        XCTAssertFalse(
            symbolsForB.contains { $0.name == "패턴 A 전용 기호" },
            "도안 전용 기호는 다른 patternID에 노출되면 안 된다"
        )
    }

    func testFavoriteSymbolOrderPersistsAfterRelaunch() async throws {
        let (store, rootURL) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try await store.saveSymbol(
            makeDraft(scope: .common, patternID: nil, name: "가나다 사용자 기호", isFavorite: true)
        )

        // 앱 재실행을 흉내내기 위해 같은 rootURL로 완전히 새 PatternStore 인스턴스를 만든다.
        let (relaunchedStore, _) = makeIsolatedStore(rootURL: rootURL)
        await relaunchedStore.load()

        let commonSymbols = relaunchedStore.commonSymbols()
        let reloaded = try XCTUnwrap(commonSymbols.first { $0.name == "가나다 사용자 기호" })
        XCTAssertTrue(reloaded.isFavorite)
        XCTAssertEqual(
            commonSymbols.first?.name,
            "가나다 사용자 기호",
            "즐겨찾기 기호가 재실행 후에도 정렬 1순위를 유지해야 한다"
        )
    }

    func testNonHTTPSLinkIsRejectedAndNotPersisted() async throws {
        let (store, rootURL) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var draft = makeDraft(scope: .common, patternID: nil, name: "잘못된 링크 기호")
        draft.linkURLString = "http://example.com"

        do {
            try await store.saveSymbol(draft)
            XCTFail("https가 아닌 링크는 저장이 거부돼야 한다")
        } catch PatternStoreError.invalidSymbolLink {
            // 예상된 실패
        }

        XCTAssertFalse(store.symbols.contains { $0.name == "잘못된 링크 기호" })

        let (reloadedStore, _) = makeIsolatedStore(rootURL: rootURL)
        await reloadedStore.load()
        XCTAssertFalse(
            reloadedStore.symbols.contains { $0.name == "잘못된 링크 기호" },
            "검증에 실패한 기호는 저장소 파일에도 반영되면 안 된다"
        )
    }

    func testSystemSymbolCannotBeEditedOrDeleted() async throws {
        let (store, rootURL) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let systemSymbol = try XCTUnwrap(store.symbols.first { $0.isSystem })

        var editDraft = makeDraft(scope: systemSymbol.scope, patternID: nil, name: "수정된 이름")
        editDraft.id = systemSymbol.id

        do {
            try await store.saveSymbol(editDraft)
            XCTFail("시스템 기호 수정은 거부돼야 한다")
        } catch PatternStoreError.systemSymbolEditNotAllowed {
            // 예상된 실패
        }

        do {
            try await store.deleteSymbol(systemSymbol.id)
            XCTFail("시스템 기호 삭제는 거부돼야 한다")
        } catch PatternStoreError.systemSymbolEditNotAllowed {
            // 예상된 실패
        }
    }

    func testViewerSymbolListIncludesOnlyFavoritedCommonSymbolsPlusPatternScoped() async throws {
        let (store, rootURL) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let patternID = UUID()
        try await store.saveSymbol(makeDraft(scope: .pattern, patternID: patternID, name: "도안 전용 기호"))

        let viewerSymbols = store.symbols(for: patternID)

        XCTAssertTrue(viewerSymbols.contains { $0.name == "도안 전용 기호" })
        // 기본 공통 기호 중 즐겨찾기된 "바늘비우기"만 포함되고, 즐겨찾기 아닌 나머지는 빠져야 한다.
        XCTAssertTrue(viewerSymbols.contains { $0.name == "바늘비우기" })
        XCTAssertFalse(viewerSymbols.contains { $0.name == "왼 코 늘리기" })
        XCTAssertFalse(viewerSymbols.contains { $0.name == "더블 스티치" })
    }

    // MARK: - Fixtures

    private func makeIsolatedStore(rootURL: URL? = nil) -> (PatternStore, URL) {
        let resolvedRootURL = rootURL ?? FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = PatternStore(
            repository: PatternRepository(rootURL: resolvedRootURL),
            fileAssetStore: FileAssetStore(
                rootURL: resolvedRootURL.appending(path: "patterns", directoryHint: .isDirectory)
            ),
            annotationRepository: AnnotationRepository(
                rootURL: resolvedRootURL.appending(path: "annotations", directoryHint: .isDirectory)
            ),
            viewerStateRepository: ViewerStateRepository(
                rootURL: resolvedRootURL.appending(path: "viewer-states", directoryHint: .isDirectory)
            ),
            symbolRepository: SymbolRepository(rootURL: resolvedRootURL)
        )
        return (store, resolvedRootURL)
    }

    private func makeDraft(
        scope: KnitSymbolScope,
        patternID: PatternItem.ID?,
        name: String,
        isFavorite: Bool = false
    ) -> KnitSymbolDraft {
        KnitSymbolDraft(
            id: nil,
            scope: scope,
            patternID: patternID,
            glyph: "그림",
            drawingStrokes: [[NormalizedPoint(x: 0.1, y: 0.1), NormalizedPoint(x: 0.6, y: 0.6)]],
            name: name,
            abbreviation: "",
            description: "",
            linkURLString: "",
            isFavorite: isFavorite
        )
    }
}
