import XCTest
@testable import YarnDrawer

final class GaugeCalculatorTests: XCTestCase {
    func testCalculatesRoundedStitchCount() throws {
        let result = try XCTUnwrap(GaugeCalculator.calculate(
            stitches: 22,
            measurementLength: 10,
            targetLength: 48
        ))

        XCTAssertEqual(result.stitchesPerCentimeter, 2.2, accuracy: 0.0001)
        XCTAssertEqual(result.rawStitchCount, 105.6, accuracy: 0.0001)
        XCTAssertEqual(result.roundedStitchCount, 106)
    }

    func testRejectsNonPositiveInput() {
        XCTAssertNil(
            GaugeCalculator.calculate(
                stitches: 0,
                measurementLength: 10,
                targetLength: 48
            )
        )
        XCTAssertNil(
            GaugeCalculator.calculate(
                stitches: 22,
                measurementLength: -1,
                targetLength: 48
            )
        )
    }
}
