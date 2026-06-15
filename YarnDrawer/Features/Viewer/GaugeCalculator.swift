import Foundation
import SwiftUI

struct GaugeResult: Equatable {
    let stitchesPerCentimeter: Double
    let rawStitchCount: Double
    let roundedStitchCount: Int
}

enum GaugeCalculator {
    static func calculate(
        stitches: Double,
        measurementLength: Double,
        targetLength: Double
    ) -> GaugeResult? {
        guard stitches > 0, measurementLength > 0, targetLength > 0 else {
            return nil
        }
        let stitchesPerCentimeter = stitches / measurementLength
        let rawStitchCount = stitchesPerCentimeter * targetLength
        return GaugeResult(
            stitchesPerCentimeter: stitchesPerCentimeter,
            rawStitchCount: rawStitchCount,
            roundedStitchCount: Int(rawStitchCount.rounded())
        )
    }
}

struct GaugeCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stitches = "22"
    @State private var measurementLength = "10"
    @State private var targetLength = "48"

    private var result: GaugeResult? {
        GaugeCalculator.calculate(
            stitches: Double(stitches) ?? 0,
            measurementLength: Double(measurementLength) ?? 0,
            targetLength: Double(targetLength) ?? 0
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    HStack(spacing: YDSpacing.x3) {
                        numberField("측정한 코 수", value: $stitches)
                        numberField("측정 길이(cm)", value: $measurementLength)
                    }
                    numberField("목표 가로 길이(cm)", value: $targetLength)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.map { "\($0.roundedStitchCount)코" } ?? "입력 확인")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(result == nil ? YDColor.danger : YDColor.yarn4)
                        Text(result.map {
                            "1cm당 \(format($0.stitchesPerCentimeter))코 · \(format($0.rawStitchCount))코를 가장 가까운 정수로 반올림"
                        } ?? "모든 값에 0보다 큰 숫자를 입력해 주세요.")
                        .font(.system(size: 12))
                        .foregroundStyle(YDColor.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(YDSpacing.x4)
                    .background(YDColor.surfaceGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(YDColor.yarn4.opacity(0.24), lineWidth: 1)
                    }
                }
                .padding(YDSpacing.x4)
            }
            .background(YDColor.cream0)
            .navigationTitle("게이지 계산기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                    .foregroundStyle(YDColor.ink)
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(YDColor.muted)
            TextField(title, text: value)
                .keyboardType(.decimalPad)
                .padding(.horizontal, YDSpacing.x3)
                .frame(minHeight: 46)
                .background(YDColor.cream0)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(YDColor.line, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1...2)))
    }
}
