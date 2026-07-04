import SwiftUI
#if DEBUG
import UIKit
#endif

@main
struct YarnDrawerApp: App {
    @StateObject private var store = PatternStore()

    init() {
        YDFont.registerFonts()
        YDFont.configureNavigationFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .font(YDFont.font(size: 15))
                .task {
                    // YARN_DRAWER_UI_TEST_MODE는 디버그 전용 검증 훅 노출 여부만 담당하고,
                    // 데이터 초기화/시드는 YARN_DRAWER_UI_TEST_RESET_DATA로 분리한다.
                    // 그래야 UI 테스트에서 앱을 terminate 후 relaunch해도(reset 없이)
                    // 이전에 저장한 데이터가 그대로 유지되는 시나리오를 검증할 수 있다.
                    if ProcessInfo.processInfo.environment["YARN_DRAWER_UI_TEST_RESET_DATA"] == "1" {
                        try? await store.deleteAllLocalData()
                        #if DEBUG
                        if ProcessInfo.processInfo.environment["YARN_DRAWER_UI_TEST_SEED_PDF"] == "1" {
                            await seedUITestPDFPattern()
                            if ProcessInfo.processInfo.environment["YARN_DRAWER_UI_TEST_SEED_MISSING_FILE"] == "1" {
                                await deleteSeededPatternFileForTesting()
                            }
                        }
                        #endif
                    } else {
                        await store.load()
                    }
                }
        }
    }

    #if DEBUG
    private func seedUITestPDFPattern() async {
        guard let sourceURL = UITestPDFFixture.makeSamplePDF() else {
            return
        }
        _ = await store.importPattern(
            PatternImportDraft(
                sourceURL: sourceURL,
                title: UITestPDFFixture.patternTitle,
                designerName: "",
                craftType: .knitting,
                tagsText: ""
            )
        )
        try? FileManager.default.removeItem(at: sourceURL)
    }

    /// 파일 누락 복구 화면(`MissingDocumentView`)을 결정론적으로 재현하기 위해,
    /// 방금 seed한 실제 PDF 패턴의 실제 파일만 디스크에서 지운다. `viewAsset` 메타데이터는
    /// 그대로 남아있으므로 `store.load()`로 `missingFilePatternIDs`를 다시 계산해야 한다.
    private func deleteSeededPatternFileForTesting() async {
        guard
            let seeded = store.patterns.first(where: { $0.title == UITestPDFFixture.patternTitle }),
            let url = await store.viewURL(for: seeded)
        else {
            return
        }
        try? FileManager.default.removeItem(at: url)
        await store.load()
    }
    #endif
}

#if DEBUG
/// UI 테스트에서 실제 PDFKitView 경로(형광펜 제스처 포함)를 태우기 위해
/// 런타임에 생성하는 1페이지 PDF. 샘플 도안(`PatternItem.samples`)은
/// `viewAsset`이 없어 항상 `SamplePatternPaper` 목업으로 빠지므로,
/// 실제 임포트 파이프라인(`PatternStore.importPattern`)을 통해 진짜 PDF
/// 도안을 하나 만들어야 실제 버그가 있는 코드 경로를 자동화 테스트가 실행할 수 있다.
enum UITestPDFFixture {
    static let patternTitle = "실사용 PDF 테스트 도안"

    static func makeSamplePDF() -> URL? {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ui-test-pattern-\(UUID().uuidString).pdf")
        let lines = [
            "1단: 겉뜨기 106코",
            "2단: 안뜨기 106코",
            "3단: 양 끝 5코 고무뜨기, 중앙 무늬 반복",
            "4단: 무늬대로 뜨기",
            "5단: 12코마다 바늘비우기 1회"
        ]
        do {
            try renderer.writePDF(to: outputURL) { context in
                context.beginPage()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24)
                ]
                var y: CGFloat = 60
                for line in lines {
                    (line as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: attributes
                    )
                    y += 60
                }
            }
            return outputURL
        } catch {
            return nil
        }
    }
}
#endif
