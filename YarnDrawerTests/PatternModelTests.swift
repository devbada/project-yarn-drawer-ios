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
            needleSizeMM: 4,
            hookSizeMM: nil
        )
        pattern.notes = "소매부터 시작"

        let encoded = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(PatternItem.self, from: encoded)

        XCTAssertEqual(decoded.gaugeInfo?.stitches, 20)
        XCTAssertEqual(decoded.materialInfo?.needleSizeMM, 4)
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
}
