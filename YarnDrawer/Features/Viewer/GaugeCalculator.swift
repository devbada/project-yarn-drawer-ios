import Foundation
import SwiftUI

struct GaugeResult: Equatable {
    let unitsPerCentimeter: Double
    let rawCount: Double
    let roundedCount: Int
}

enum GaugeCalculator {
    /// 코 수와 단 수 계산에 공통으로 쓰는 축 중립 계산. `count`는 측정한 코 수 또는 단 수,
    /// `targetLength`는 그 축(가로/세로)의 목표 길이다.
    static func calculate(
        count: Double,
        measurementLength: Double,
        targetLength: Double
    ) -> GaugeResult? {
        guard count > 0, measurementLength > 0, targetLength > 0 else {
            return nil
        }
        let unitsPerCentimeter = count / measurementLength
        let rawCount = unitsPerCentimeter * targetLength
        return GaugeResult(
            unitsPerCentimeter: unitsPerCentimeter,
            rawCount: rawCount,
            roundedCount: Int(rawCount.rounded())
        )
    }

    /// 현재 뜬 코 수 또는 단 수를 기준으로 실제 길이를 역산한다.
    static func actualLength(
        count: Double,
        measuredCount: Double,
        measurementLength: Double
    ) -> Double? {
        guard count > 0, measuredCount > 0, measurementLength > 0 else {
            return nil
        }
        return count * measurementLength / measuredCount
    }
}

struct GaugeCalculatorView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.dismiss) private var dismiss
    let pattern: PatternItem

    @State private var stitches: String
    @State private var rows: String
    @State private var measurementLength: String
    @State private var targetWidth = "48"
    @State private var targetHeight = ""
    @State private var currentStitches = ""
    @State private var currentRows = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveMessageIsError = false

    init(pattern: PatternItem) {
        self.pattern = pattern
        let gauge = pattern.gaugeInfo
        _stitches = State(initialValue: gauge?.stitches.map(Self.numberText) ?? "22")
        _rows = State(initialValue: gauge?.rows.map(Self.numberText) ?? "")
        _measurementLength = State(initialValue: gauge?.measurementLengthCM.map(Self.numberText) ?? "10")
    }

    private var stitchResult: GaugeResult? {
        GaugeCalculator.calculate(
            count: Double(stitches) ?? 0,
            measurementLength: Double(measurementLength) ?? 0,
            targetLength: Double(targetWidth) ?? 0
        )
    }

    private var rowResult: GaugeResult? {
        GaugeCalculator.calculate(
            count: Double(rows) ?? 0,
            measurementLength: Double(measurementLength) ?? 0,
            targetLength: Double(targetHeight) ?? 0
        )
    }

    private var actualLengthFromCurrentStitches: Double? {
        GaugeCalculator.actualLength(
            count: Double(currentStitches) ?? 0,
            measuredCount: Double(stitches) ?? 0,
            measurementLength: Double(measurementLength) ?? 0
        )
    }

    private var actualLengthFromCurrentRows: Double? {
        GaugeCalculator.actualLength(
            count: Double(currentRows) ?? 0,
            measuredCount: Double(rows) ?? 0,
            measurementLength: Double(measurementLength) ?? 0
        )
    }

    private var showsRowSection: Bool {
        !rows.trimmingCharacters(in: .whitespaces).isEmpty ||
            !targetHeight.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    HStack(spacing: YDSpacing.x3) {
                        numberField("측정한 코 수", value: $stitches)
                        numberField("측정한 단 수", value: $rows)
                    }
                    numberField("측정 길이(cm)", value: $measurementLength)
                    HStack(spacing: YDSpacing.x3) {
                        numberField("목표 가로 길이(cm)", value: $targetWidth)
                        numberField("목표 세로 길이(cm)", value: $targetHeight)
                    }

                    resultCard(
                        title: stitchResult.map { "\($0.roundedCount)코" } ?? "코 수 입력 확인",
                        detail: stitchResult.map {
                            "1cm당 \(format($0.unitsPerCentimeter))코 · \(format($0.rawCount))코를 가장 가까운 정수로 반올림"
                        } ?? "측정한 코 수, 측정 길이, 목표 가로 길이에 0보다 큰 숫자를 입력해 주세요.",
                        isValid: stitchResult != nil
                    )

                    if showsRowSection {
                        resultCard(
                            title: rowResult.map { "\($0.roundedCount)단" } ?? "단 수 입력 확인",
                            detail: rowResult.map {
                                "1cm당 \(format($0.unitsPerCentimeter))단 · \(format($0.rawCount))단을 가장 가까운 정수로 반올림"
                            } ?? "측정한 단 수, 측정 길이, 목표 세로 길이에 0보다 큰 숫자를 입력해 주세요.",
                            isValid: rowResult != nil
                        )
                    }

                    VStack(alignment: .leading, spacing: YDSpacing.x3) {
                        Text("현재 코·단 수 기준 실제 길이")
                            .font(YDFont.font(size: 13, weight: .heavy))
                            .foregroundStyle(YDColor.ink)
                        HStack(spacing: YDSpacing.x3) {
                            numberField("현재 코 수", value: $currentStitches)
                            numberField("현재 단 수", value: $currentRows)
                        }
                        if let actualLengthFromCurrentStitches {
                            Text("현재 코 수 기준 실제 가로 길이: 약 \(format(actualLengthFromCurrentStitches))cm")
                                .font(YDFont.font(size: 12, weight: .bold))
                                .foregroundStyle(YDColor.yarn4)
                        }
                        if let actualLengthFromCurrentRows {
                            Text("현재 단 수 기준 실제 세로 길이: 약 \(format(actualLengthFromCurrentRows))cm")
                                .font(YDFont.font(size: 12, weight: .bold))
                                .foregroundStyle(YDColor.yarn4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(YDSpacing.x4)
                    .background(YDColor.cream0)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(YDColor.line, lineWidth: 1)
                    }

                    if pattern.isSample {
                        Text("샘플 도안은 게이지를 저장할 수 없습니다.")
                            .font(YDFont.font(size: 13, weight: .bold))
                            .foregroundStyle(YDColor.wood3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(YDColor.wood1.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Button(isSaving ? "저장 중" : "상세정보에 게이지 저장") {
                            saveToDetails()
                        }
                        .buttonStyle(YDPrimaryButtonStyle())
                        .disabled(isSaving || (stitchResult == nil && rowResult == nil))
                    }

                    if let saveMessage {
                        Text(saveMessage)
                            .font(YDFont.font(size: 13, weight: .bold))
                            .foregroundStyle(saveMessageIsError ? YDColor.danger : YDColor.yarn4)
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

    private func resultCard(title: String, detail: String, isValid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(YDFont.font(size: 24, weight: .bold))
                .foregroundStyle(isValid ? YDColor.yarn4 : YDColor.danger)
            Text(detail)
                .font(YDFont.font(size: 12))
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

    private func numberField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(YDFont.font(size: 12, weight: .heavy))
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

    private static func numberText(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private func saveToDetails() {
        isSaving = true
        saveMessage = nil
        Task {
            defer { isSaving = false }
            do {
                guard var updated = store.pattern(id: pattern.id) else {
                    throw PatternStoreError.patternNotFound
                }
                updated.gaugeInfo = PatternGaugeInfo(
                    stitches: Double(stitches),
                    rows: Double(rows),
                    measurementLengthCM: Double(measurementLength)
                )
                try await store.updatePattern(updated)
                saveMessageIsError = false
                saveMessage = "게이지를 상세정보에 저장했습니다."
            } catch {
                saveMessageIsError = true
                saveMessage = error.localizedDescription
            }
        }
    }
}
