import XCTest
@testable import YarnDrawer

final class GaugeCalculatorTests: XCTestCase {
    func testCalculatesRoundedStitchCount() throws {
        let result = try XCTUnwrap(GaugeCalculator.calculate(
            count: 22,
            measurementLength: 10,
            targetLength: 48
        ))

        XCTAssertEqual(result.unitsPerCentimeter, 2.2, accuracy: 0.0001)
        XCTAssertEqual(result.rawCount, 105.6, accuracy: 0.0001)
        XCTAssertEqual(result.roundedCount, 106)
    }

    func testCalculatesRoundedRowCount() throws {
        // 같은 함수를 단 수 계산에도 그대로 재사용한다(코와 단은 축만 다를 뿐 계산식이 같다).
        let result = try XCTUnwrap(GaugeCalculator.calculate(
            count: 30,
            measurementLength: 10,
            targetLength: 60
        ))

        XCTAssertEqual(result.unitsPerCentimeter, 3.0, accuracy: 0.0001)
        XCTAssertEqual(result.rawCount, 180, accuracy: 0.0001)
        XCTAssertEqual(result.roundedCount, 180)
    }

    func testRejectsNonPositiveInput() {
        XCTAssertNil(
            GaugeCalculator.calculate(
                count: 0,
                measurementLength: 10,
                targetLength: 48
            )
        )
        XCTAssertNil(
            GaugeCalculator.calculate(
                count: 22,
                measurementLength: -1,
                targetLength: 48
            )
        )
    }

    func testActualLengthFromCurrentCount() throws {
        let length = try XCTUnwrap(
            GaugeCalculator.actualLength(count: 106, measuredCount: 22, measurementLength: 10)
        )
        XCTAssertEqual(length, 48.181818, accuracy: 0.0001)
    }

    func testActualLengthRejectsNonPositiveInput() {
        XCTAssertNil(GaugeCalculator.actualLength(count: 0, measuredCount: 22, measurementLength: 10))
        XCTAssertNil(GaugeCalculator.actualLength(count: 106, measuredCount: 0, measurementLength: 10))
        XCTAssertNil(GaugeCalculator.actualLength(count: 106, measuredCount: 22, measurementLength: -1))
    }
}
