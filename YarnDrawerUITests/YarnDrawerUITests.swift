import UIKit
import XCTest

final class YarnDrawerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLibrarySampleViewerAndViewModeSmoke() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["내 도안"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["브라운 울 가디건 도안 열기"].waitForExistence(timeout: 5))

        app.buttons["브라운 울 가디건 도안 열기"].tap()

        XCTAssertTrue(app.staticTexts["브라운 울 가디건"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["보기"].waitForExistence(timeout: 5))

        app.buttons["보기"].tap()

        XCTAssertTrue(app.staticTexts["보기모드로 전환했습니다."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["몸판 뜨기"].exists)

        app.buttons["보관함으로 돌아가기"].tap()

        XCTAssertTrue(app.staticTexts["내 도안"].waitForExistence(timeout: 5))
    }

    /// 샘플 도안은 항상 `viewAsset`이 없어 `SamplePatternPaper` 목업으로만 열리기 때문에,
    /// 실제 PDFKit 형광펜 제스처는 이 목업으로 검증할 수 없다. `YARN_DRAWER_UI_TEST_RESET_DATA` +
    /// `YARN_DRAWER_UI_TEST_SEED_PDF`로 실제 임포트 파이프라인을 통해 진짜 PDF 도안을 하나 만들어
    /// 실제 `PDFKitView` 경로에서 다음을 모두 검증한다.
    /// 1. 노랑이 아닌 팔레트 색상(민트)을 선택해 드래그하면 저장된 annotation의 `highlightHex`가
    ///    실제로 그 색상인지(디버그 훅으로 결정론적 검증)
    /// 2. 화면에 실제로 그 색이 렌더링되는지(스크린샷 픽셀 샘플링, 드래그 전/후 비교)
    /// 3. 앱을 완전히 종료(terminate) 후 재실행해도(reset 없이) 저장된 형광펜이 유지되는지
    func testFreehandHighlightAppliesColorAndPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_SEED_PDF"] = "1"
        app.launch()

        // importPattern()이 성공하면 store.selectedPattern이 즉시 설정되어
        // 라이브러리 화면 대신 바로 뷰어가 뜬다(실제 등록 UX와 동일).
        XCTAssertTrue(app.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["형광펜"].waitForExistence(timeout: 8))
        app.buttons["형광펜"].tap()

        XCTAssertTrue(
            app.staticTexts["한 손가락 드래그: 형광펜 · 두 손가락 드래그: 이동"]
                .waitForExistence(timeout: 5)
        )

        // 노랑(기본값)이 아닌 민트 형광펜을 명시적으로 선택한다.
        let mintSwatch = app.buttons["민트 형광펜"]
        XCTAssertTrue(mintSwatch.waitForExistence(timeout: 5))
        mintSwatch.tap()

        let baselineState = try readDebugHighlightState(app)
        XCTAssertEqual(baselineState.highlightCount, 0, "드래그 전에는 저장된 형광펜이 없어야 한다")

        let beforeDragScreenshot = app.screenshot().image
        let baselineMintPixels = mintLikePixelCount(in: beforeDragScreenshot)

        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55))
        start.press(forDuration: 0.2, thenDragTo: end)

        XCTAssertTrue(
            app.staticTexts["형광펜 표시를 저장했습니다."].waitForExistence(timeout: 8)
        )

        // 1) 저장된 annotation의 색상이 실제로 선택한 민트인지 디버그 훅으로 검증한다.
        let afterDragState = try readDebugHighlightState(app)
        XCTAssertEqual(afterDragState.highlightCount, 1)
        XCTAssertEqual(
            afterDragState.lastHex,
            "80E5D2",
            "저장된 형광펜의 highlightHex가 선택한 민트 색상과 일치해야 한다"
        )

        // 2) 화면에 실제로 그 색이 렌더링됐는지 드래그 전/후 픽셀 샘플링으로 비교한다.
        let afterDragScreenshot = app.screenshot().image
        let afterDragMintPixels = mintLikePixelCount(in: afterDragScreenshot)
        XCTAssertGreaterThanOrEqual(
            afterDragMintPixels - baselineMintPixels,
            15,
            "드래그 후 민트 계열 픽셀이 뚜렷하게 늘어나야 한다(baseline: \(baselineMintPixels), after: \(afterDragMintPixels))"
        )

        attachScreenshot(app, image: beforeDragScreenshot, name: "before-drag")
        attachScreenshot(app, image: afterDragScreenshot, name: "after-drag")

        // 3) 앱을 완전히 종료했다가(terminate) reset 없이 재실행해도 저장된 형광펜이 유지되는지 확인한다.
        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        relaunchedApp.launch()

        XCTAssertTrue(relaunchedApp.staticTexts["내 도안"].waitForExistence(timeout: 8))
        let reopenButton = relaunchedApp.buttons["실사용 PDF 테스트 도안 도안 열기"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 8))
        reopenButton.tap()

        XCTAssertTrue(relaunchedApp.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))

        let afterRelaunchState = try readDebugHighlightState(relaunchedApp)
        XCTAssertEqual(
            afterRelaunchState.highlightCount,
            1,
            "앱 재실행 후에도 저장된 형광펜 개수가 유지돼야 한다"
        )
        XCTAssertEqual(
            afterRelaunchState.lastHex,
            "80E5D2",
            "앱 재실행 후에도 저장된 형광펜 색상이 유지돼야 한다"
        )

        let afterRelaunchScreenshot = relaunchedApp.screenshot().image
        let afterRelaunchMintPixels = mintLikePixelCount(in: afterRelaunchScreenshot)
        XCTAssertGreaterThanOrEqual(
            afterRelaunchMintPixels,
            15,
            "재실행 후 재진입해도 화면에 민트 형광펜이 다시 렌더링돼야 한다"
        )
        attachScreenshot(relaunchedApp, image: afterRelaunchScreenshot, name: "after-relaunch-reopen")

        // 재진입 시 형광펜 도구가 AppStorage로 이미 복원된 상태에서(도구 버튼을 다시 탭하지 않고)
        // 곧바로 두 번째 드래그가 먹히는지 확인한다. 문서가 막 로드된 직후 상태에서의
        // 제스처 레이스 컨디션을 노린다.
        XCTAssertTrue(relaunchedApp.buttons["형광펜"].exists)
        let relaunchedWindow = relaunchedApp.windows.firstMatch
        let secondStart = relaunchedWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42))
        let secondEnd = relaunchedWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        secondStart.press(forDuration: 0.2, thenDragTo: secondEnd)

        XCTAssertTrue(
            relaunchedApp.staticTexts["형광펜 표시를 저장했습니다."].waitForExistence(timeout: 8)
        )
        let afterSecondDragState = try readDebugHighlightState(relaunchedApp)
        XCTAssertEqual(
            afterSecondDragState.highlightCount,
            2,
            "재실행 후에도 새 형광펜 드래그가 추가로 저장돼야 한다"
        )
    }

    /// `PatternStore.viewURL(for:)`은 실제 파일 존재 여부와 무관하게 `pattern.viewAsset`만
    /// 보고 URL을 만들기 때문에, `store.missingFilePatternIDs` 기준으로 판단하지 않으면
    /// 파일이 실제로 사라져도 복구 화면이 뜨지 않는다(빈 PDFKitView만 보임). 이 회귀를
    /// 막기 위해 `YARN_DRAWER_UI_TEST_SEED_MISSING_FILE`로 seed 직후 파일을 지운 상태를
    /// 만들고, 복구 안내·진입점·재연결까지 실제로 동작하는지 검증한다.
    func testMissingFileShowsRecoveryEntryPointAndReconnects() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_SEED_PDF"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_SEED_MISSING_FILE"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["작업용 파일을 열 수 없습니다."].waitForExistence(timeout: 8),
            "파일이 실제로 없어졌을 때 복구 안내가 보여야 한다"
        )
        XCTAssertTrue(app.buttons["파일 다시 선택"].waitForExistence(timeout: 5))

        // 시스템 문서 picker는 UI 테스트로 자동화하기 어려우므로, DEBUG 전용 훅으로
        // 실제 재연결 파이프라인(store.reconnectPatternFile)을 바로 태운다.
        let debugReconnectButton = app.buttons["테스트용 파일로 재연결"]
        XCTAssertTrue(debugReconnectButton.waitForExistence(timeout: 5))
        debugReconnectButton.tap()

        XCTAssertTrue(
            app.staticTexts["파일을 다시 연결했습니다."].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.staticTexts["작업용 파일을 열 수 없습니다."].exists)
        // PDFKit은 문서 텍스트를 StaticText가 아니라 Other 타입 접근성 요소로 노출한다.
        XCTAssertTrue(
            app.otherElements["1단: 겉뜨기 106코"].waitForExistence(timeout: 8),
            "재연결 후 실제 문서 내용이 렌더링돼야 한다"
        )
    }

    /// 저장이 실패했을 때 사용자가 인지하고 재시도할 수 있는 진입점이 실제로 동작하는지
    /// `YARN_DRAWER_UI_TEST_FORCE_SAVE_FAILURE_COUNT`로 결정론적으로 검증한다.
    func testSaveFailureShowsRetryEntryPointAndRecovers() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_SEED_PDF"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_FORCE_SAVE_FAILURE_COUNT"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["체크"].waitForExistence(timeout: 8))
        app.buttons["체크"].tap()

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)).tap()

        let retryButton = app.buttons["저장 다시 시도"]
        XCTAssertTrue(
            retryButton.waitForExistence(timeout: 8),
            "저장 실패 상태에서는 탭 가능한 재시도 진입점이 보여야 한다"
        )

        retryButton.tap()

        // 성공 토스트는 일정 시간 뒤 자동으로 사라지는 일시적 신호라 타이밍에 취약하다.
        // 실제로 중요한 건 지속되는 상태 표시이므로, 재시도 버튼이 사라지고 정상 상태
        // 문구로 돌아오는지를 기준으로 검증한다(요구사항: toast만으로 전달하지 말 것).
        let normalStatus = app.staticTexts["편집 상태 · 저장됨"]
        XCTAssertTrue(
            normalStatus.waitForExistence(timeout: 8),
            "재시도가 성공하면 지속 상태 문구가 정상 저장 상태로 돌아와야 한다"
        )
        XCTAssertFalse(
            app.buttons["저장 다시 시도"].exists,
            "재시도가 성공하면 실패 상태/재시도 버튼이 사라져야 한다"
        )
    }

    /// 회귀 검증: 첫 번째 annotation 저장이 실패한 뒤, 사용자가 재시도 버튼을 누르지 않고
    /// 바로 두 번째 annotation을 추가해도 두 변경 모두 유지돼야 한다. 이전 구현은
    /// 새 편집을 시작할 때마다 `annotationSaveFailed`를 무조건 false로 지우고, 첫 저장
    /// 실패 이후 후속 편집도 여전히 단일 append 경로를 탔기 때문에 첫 번째(실패한) 변경이
    /// 파일에 기록되지 못한 채 "저장됨" 상태로 되돌아갈 수 있었다.
    func testUnretriedEditAfterSaveFailureIsNotLostAndPersistsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_SEED_PDF"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_FORCE_SAVE_FAILURE_COUNT"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["체크"].waitForExistence(timeout: 8))
        app.buttons["체크"].tap()

        let window = app.windows.firstMatch

        // 첫 번째 체크: 강제로 저장이 실패해야 한다.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.32)).tap()
        let retryButton = app.buttons["저장 다시 시도"]
        XCTAssertTrue(
            retryButton.waitForExistence(timeout: 8),
            "첫 번째 저장은 강제로 실패해야 한다"
        )

        // 재시도 버튼을 누르지 않고, 서로 겹치지 않는 다른 위치에 두 번째 체크를 추가한다.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55)).tap()

        // 두 번째 저장은 강제 실패 카운터가 이미 소진돼 성공해야 하고, 그 성공은
        // 전체 snapshot 저장이어야 하므로 첫 번째(이전에 실패한) 체크까지 함께 기록돼야 한다.
        XCTAssertTrue(
            app.staticTexts["편집 상태 · 저장됨"].waitForExistence(timeout: 8),
            "두 번째 저장이 성공하면 실패 상태가 해소돼야 한다"
        )
        XCTAssertFalse(app.buttons["저장 다시 시도"].exists)

        let stateBeforeRelaunch = try readDebugHighlightState(app)
        XCTAssertEqual(
            stateBeforeRelaunch.total,
            2,
            "재시도 없이 이어간 두 번째 편집이 성공하면 두 annotation이 모두 메모리에 있어야 한다"
        )

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        relaunchedApp.launch()

        XCTAssertTrue(relaunchedApp.staticTexts["내 도안"].waitForExistence(timeout: 8))
        let reopenButton = relaunchedApp.buttons["실사용 PDF 테스트 도안 도안 열기"]
        XCTAssertTrue(reopenButton.waitForExistence(timeout: 8))
        reopenButton.tap()

        XCTAssertTrue(relaunchedApp.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))
        let stateAfterRelaunch = try readDebugHighlightState(relaunchedApp)
        XCTAssertEqual(
            stateAfterRelaunch.total,
            2,
            "첫 번째 저장 실패 이후 재시도 없이 이어간 편집도 앱을 완전히 재실행한 뒤 모두 남아 있어야 한다"
        )
    }

    /// 기호 라이브러리(`SymbolsView`)의 검색, 즐겨찾기 필터, 등록/수정/삭제 흐름을 검증한다.
    /// Canvas 드로잉은 `symbolCanvas` 접근성 식별자를 기준으로 그 엘리먼트 자신의 좌표계에
    /// 드래그해, 화면 레이아웃이 바뀌어도 깨지지 않게 한다.
    func testSymbolLibrarySearchFilterAddEditDelete() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["내 도안"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["기호"].waitForExistence(timeout: 5))
        app.buttons["기호"].tap()

        XCTAssertTrue(app.staticTexts["바늘비우기"].waitForExistence(timeout: 5))

        let symbolName = "테스트 기호 \(Int.random(in: 1000...9999))"

        app.buttons["새 기호 등록"].tap()
        XCTAssertTrue(app.navigationBars["기호 등록"].waitForExistence(timeout: 5))

        drawOnSymbolCanvas(app)

        let nameField = app.textFields["예: 바늘비우기"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(symbolName)

        app.buttons["저장"].tap()

        XCTAssertTrue(app.staticTexts["기호를 등록했습니다."].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts[symbolName].waitForExistence(timeout: 5),
            "새로 등록한 기호가 목록에 바로 보여야 한다"
        )

        // 검색: 새 기호 이름으로 검색하면 다른 기본 기호는 걸러져야 한다.
        let searchField = app.textFields["기호명, 약어 검색"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(symbolName)
        XCTAssertTrue(app.staticTexts[symbolName].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["바늘비우기"].exists, "검색어와 무관한 기본 기호는 숨겨져야 한다")
        clearTextField(searchField)

        // 즐겨찾기 필터: 새 기호는 즐겨찾기가 아니므로 필터를 켜면 목록에서 빠져야 한다.
        app.buttons["즐겨찾기"].tap()
        XCTAssertFalse(
            app.staticTexts[symbolName].exists,
            "즐겨찾기 필터에서는 즐겨찾기하지 않은 새 기호가 보이면 안 된다"
        )
        XCTAssertTrue(
            app.staticTexts["바늘비우기"].waitForExistence(timeout: 5),
            "기본 즐겨찾기 기호는 즐겨찾기 필터에서도 보여야 한다"
        )
        app.buttons["전체"].tap()

        // 수정: 상세로 들어가 수정 화면을 열면 이름과 그린 선이 그대로 남아있어야 한다.
        XCTAssertTrue(app.staticTexts[symbolName].waitForExistence(timeout: 5))
        app.staticTexts[symbolName].tap()
        XCTAssertTrue(app.buttons["수정"].waitForExistence(timeout: 5))
        app.buttons["수정"].tap()

        XCTAssertTrue(app.navigationBars["기호 수정"].waitForExistence(timeout: 5))
        let editingNameField = app.textFields["예: 바늘비우기"]
        XCTAssertTrue(editingNameField.waitForExistence(timeout: 5))
        XCTAssertEqual(editingNameField.value as? String, symbolName)
        XCTAssertTrue(
            app.staticTexts["그린 기호가 카드와 뷰어에 표시됩니다."].waitForExistence(timeout: 5),
            "수정 화면을 다시 열어도 이전에 그린 획이 남아있어야 한다"
        )
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["기호를 수정했습니다."].waitForExistence(timeout: 8))

        // 삭제
        XCTAssertTrue(app.staticTexts[symbolName].waitForExistence(timeout: 5))
        app.staticTexts[symbolName].tap()
        XCTAssertTrue(app.buttons["삭제"].waitForExistence(timeout: 5))
        app.buttons["삭제"].tap()
        XCTAssertTrue(app.buttons["삭제"].waitForExistence(timeout: 5))
        app.buttons["삭제"].tap()

        XCTAssertTrue(app.staticTexts["기호를 삭제했습니다."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[symbolName].exists, "삭제한 기호는 목록에서 사라져야 한다")
    }

    /// 뷰어의 현재 도안 기호 floating 패널이 하드코딩 없이 저장소 데이터를 쓰고, 새로 등록한
    /// 도안 전용 기호가 패널을 벗어나지 않고 바로 반영되는지 확인한다.
    func testViewerSymbolPanelReflectsPatternSpecificSymbolImmediately() throws {
        let app = XCUIApplication()
        app.launchEnvironment["YARN_DRAWER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_RESET_DATA"] = "1"
        app.launchEnvironment["YARN_DRAWER_UI_TEST_SEED_PDF"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["실사용 PDF 테스트 도안"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["현재 도안 기호 열기"].waitForExistence(timeout: 8))
        app.buttons["현재 도안 기호 열기"].tap()

        XCTAssertTrue(app.navigationBars["현재 도안 기호"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["바늘비우기"].waitForExistence(timeout: 5),
            "즐겨찾기한 공통 기호는 도안 기호 패널에도 보여야 한다"
        )

        let symbolName = "도안 전용 기호 \(Int.random(in: 1000...9999))"
        app.buttons["등록"].tap()
        XCTAssertTrue(app.navigationBars["기호 등록"].waitForExistence(timeout: 5))

        drawOnSymbolCanvas(app)

        let nameField = app.textFields["예: 바늘비우기"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(symbolName)

        app.buttons["저장"].tap()

        XCTAssertTrue(app.staticTexts["기호를 등록했습니다."].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts[symbolName].waitForExistence(timeout: 5),
            "패널을 나가지 않고도 새로 만든 도안 전용 기호가 바로 보여야 한다"
        )
    }

    /// 일반 SwiftUI `TextField`는 UIKit의 clear 버튼이 없으므로, 현재 값 길이만큼
    /// backspace를 보내 지운다.
    private func clearTextField(_ field: XCUIElement) {
        field.tap()
        guard let currentValue = field.value as? String, !currentValue.isEmpty else {
            return
        }
        let deleteString = String(
            repeating: XCUIKeyboardKey.delete.rawValue,
            count: currentValue.count
        )
        field.typeText(deleteString)
    }

    private func drawOnSymbolCanvas(_ app: XCUIApplication) {
        let canvas = app.otherElements["symbolCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "기호 그리기 canvas를 찾지 못했다")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let mid = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: mid)
        mid.press(forDuration: 0.05, thenDragTo: end)
    }

    private func attachScreenshot(_ app: XCUIApplication, image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// `PatternViewerView`가 `#if DEBUG` + `YARN_DRAWER_UI_TEST_MODE`일 때만 노출하는
    /// `debugHighlightState` 접근성 요소에서 "totalCount=N;highlightCount=N;lastHighlightHex=XXXXXX"
    /// 형식의 문자열을 읽어 파싱한다. `total`은 형광펜이 아닌 체크/메모/현재 줄 등을 포함한
    /// 전체 annotation 개수다. 일반 빌드/릴리즈에서는 이 요소 자체가 존재하지 않는다.
    private func readDebugHighlightState(
        _ app: XCUIApplication,
        timeout: TimeInterval = 8
    ) throws -> (total: Int, highlightCount: Int, lastHex: String) {
        let element = app.staticTexts.matching(identifier: "debugHighlightState").firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "디버그 전용 highlight 상태 훅을 찾지 못했다"
        )
        let label = element.label
        let parts = label
            .split(separator: ";")
            .reduce(into: [String: String]()) { result, part in
                let keyValue = part.split(separator: "=", maxSplits: 1)
                guard keyValue.count == 2 else { return }
                result[String(keyValue[0])] = String(keyValue[1])
            }
        guard
            let totalString = parts["totalCount"],
            let total = Int(totalString),
            let highlightCountString = parts["highlightCount"],
            let highlightCount = Int(highlightCountString),
            let lastHex = parts["lastHighlightHex"]
        else {
            XCTFail("디버그 상태 문자열을 파싱하지 못했다: \(label)")
            return (0, 0, "")
        }
        return (total, highlightCount, lastHex)
    }

    /// 스크린샷에서 형광펜 색(민트, `80E5D2`, alpha 0.48로 흰 배경 위에 합성됨 ≈ RGB(194,233,243))과
    /// 유사한 픽셀 수를 센다. 채널 순서(RGBA/BGRA)에 의존하지 않도록 세 채널 값을 정렬해
    /// "한 채널만 확연히 낮고 나머지 두 채널이 서로 비슷하게 높은" 신호로 판정하며,
    /// 흰 배경·검은 텍스트는 명시적으로 제외한다. 같은 화면 레이아웃에서 찍은 두 스크린샷을
    /// 드래그 전/후로 비교하는 용도라 원점(top-left vs bottom-left) 해석이 달라도 일관성이 깨지지 않는다.
    private func mintLikePixelCount(in image: UIImage) -> Int {
        guard
            let cgImage = image.cgImage,
            let data = cgImage.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            return 0
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        let bytesPerRow = cgImage.bytesPerRow
        let dataLength = CFDataGetLength(data)

        // 문서 영역(상단 안내 pill과 하단 팔레트/툴바 사이) 대략의 범위만 성긴 간격으로 스캔한다.
        let minX = Int(Double(width) * 0.05)
        let maxX = Int(Double(width) * 0.95)
        let minY = Int(Double(height) * 0.22)
        let maxY = Int(Double(height) * 0.60)
        let step = 6

        var count = 0
        var y = minY
        while y < maxY {
            var x = minX
            while x < maxX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset + 2 < dataLength {
                    let values = [Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])]
                        .sorted()
                    let isWhiteish = values[0] > 230
                    let isDarkText = values[2] < 120
                    let hasMintSignature = (values[2] - values[0]) > 35 && values[1] > 150
                    if !isWhiteish, !isDarkText, hasMintSignature {
                        count += 1
                    }
                }
                x += step
            }
            y += step
        }
        return count
    }
}
