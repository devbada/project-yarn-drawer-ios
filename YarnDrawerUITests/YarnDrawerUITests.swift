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
        XCTAssertEqual(baselineState.count, 0, "드래그 전에는 저장된 형광펜이 없어야 한다")

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
        XCTAssertEqual(afterDragState.count, 1)
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
            afterRelaunchState.count,
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
            afterSecondDragState.count,
            2,
            "재실행 후에도 새 형광펜 드래그가 추가로 저장돼야 한다"
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// `PatternViewerView`가 `#if DEBUG` + `YARN_DRAWER_UI_TEST_MODE`일 때만 노출하는
    /// `debugHighlightState` 접근성 요소에서 "highlightCount=N;lastHighlightHex=XXXXXX" 형식의
    /// 문자열을 읽어 파싱한다. 일반 빌드/릴리즈에서는 이 요소 자체가 존재하지 않는다.
    private func readDebugHighlightState(
        _ app: XCUIApplication,
        timeout: TimeInterval = 8
    ) throws -> (count: Int, lastHex: String) {
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
            let countString = parts["highlightCount"],
            let count = Int(countString),
            let lastHex = parts["lastHighlightHex"]
        else {
            XCTFail("디버그 상태 문자열을 파싱하지 못했다: \(label)")
            return (0, "")
        }
        return (count, lastHex)
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
