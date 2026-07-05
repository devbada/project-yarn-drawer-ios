import XCTest
@testable import YarnDrawer

final class PatternModelTests: XCTestCase {
    func testImportDraftNormalizesAndDeduplicatesTags() {
        let draft = PatternImportDraft(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.jpg"),
            title: "샘플",
            designerName: "",
            craftType: .crochet,
            tagsText: "레이스, 코튼, 레이스,  여름 "
        )

        XCTAssertEqual(draft.tags, ["레이스", "코튼", "여름"])
    }

    func testSearchableTextIncludesMetadata() {
        let pattern = PatternItem.samples[0]

        XCTAssertTrue(pattern.searchableText.contains("브라운 울 가디건"))
        XCTAssertTrue(pattern.searchableText.contains("knit.mori"))
        XCTAssertTrue(pattern.searchableText.contains("메리노 울"))
    }

    func testDetailsRoundTripKeepsGaugeAndMaterialInformation() throws {
        var pattern = PatternItem.samples[0]
        pattern.isSample = false
        pattern.gaugeInfo = PatternGaugeInfo(
            stitches: 20,
            rows: 28,
            measurementLengthCM: 10
        )
        pattern.materialInfo = PatternMaterialInfo(
            yarnName: "메리노 울",
            yarnWeight: "DK",
            fiberContent: "메리노 100%",
            yarnAmount: "3볼(450g)",
            yarnColor: "네이비",
            needleSizeMM: 4,
            hookSizeMM: nil
        )
        pattern.notes = "소매부터 시작"

        let encoded = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(PatternItem.self, from: encoded)

        XCTAssertEqual(decoded.gaugeInfo?.stitches, 20)
        XCTAssertEqual(decoded.gaugeInfo?.rows, 28)
        XCTAssertEqual(decoded.materialInfo?.needleSizeMM, 4)
        XCTAssertEqual(decoded.materialInfo?.fiberContent, "메리노 100%")
        XCTAssertEqual(decoded.materialInfo?.yarnAmount, "3볼(450g)")
        XCTAssertEqual(decoded.materialInfo?.yarnColor, "네이비")
        XCTAssertEqual(decoded.notes, "소매부터 시작")
        XCTAssertTrue(decoded.searchableText.contains("dk"))
    }

    func testLegacyPatternWithoutDetailFieldsStillDecodes() throws {
        let encoded = try JSONEncoder().encode(PatternItem.samples[0])
        let decoded = try JSONDecoder().decode(PatternItem.self, from: encoded)

        XCTAssertNil(decoded.gaugeInfo)
        XCTAssertNil(decoded.materialInfo)
        XCTAssertNil(decoded.notes)
    }

    func testLegacyMaterialInfoWithoutNewFieldsStillDecodes() throws {
        let json = """
        {
          "yarnName": "메리노 울",
          "yarnWeight": "DK",
          "needleSizeMM": 4
        }
        """
        let decoded = try JSONDecoder().decode(PatternMaterialInfo.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.yarnName, "메리노 울")
        XCTAssertEqual(decoded.needleSizeMM, 4)
        XCTAssertNil(decoded.fiberContent, "구버전 JSON에 없던 필드는 안전하게 nil로 복원돼야 한다")
        XCTAssertNil(decoded.yarnAmount)
        XCTAssertNil(decoded.yarnColor)
    }
}
