import SwiftUI

struct PatternDetailsView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.dismiss) private var dismiss

    let patternID: PatternItem.ID
    var onDeleted: () -> Void = {}

    @State private var title = ""
    @State private var designerName = ""
    @State private var craftType: CraftType = .knitting
    @State private var tagsText = ""
    @State private var gaugeStitches = ""
    @State private var gaugeRows = ""
    @State private var gaugeLength = ""
    @State private var yarnName = ""
    @State private var yarnWeight = ""
    @State private var needleSize = ""
    @State private var hookSize = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    if let pattern {
                        if pattern.isSample {
                            readOnlyNotice
                        }

                        section("기본 정보") {
                            field("도안명") {
                                TextField("필수", text: $title)
                            }
                            field("작가명") {
                                TextField("선택", text: $designerName)
                            }
                            field("종류") {
                                Picker("종류", selection: $craftType) {
                                    ForEach(CraftType.allCases) { type in
                                        Text(type.title).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            field("태그") {
                                TextField("레이스, 여름, 코튼", text: $tagsText)
                            }
                        }

                        section("게이지") {
                            HStack(spacing: YDSpacing.x2) {
                                numberField("코 수", text: $gaugeStitches)
                                numberField("단 수", text: $gaugeRows)
                                numberField("기준 cm", text: $gaugeLength)
                            }
                        }

                        section("실과 바늘") {
                            field("실 이름") {
                                TextField("선택", text: $yarnName)
                            }
                            field("실 굵기") {
                                TextField("예: DK, 4ply", text: $yarnWeight)
                            }
                            HStack(spacing: YDSpacing.x2) {
                                numberField("대바늘 mm", text: $needleSize)
                                numberField("코바늘 mm", text: $hookSize)
                            }
                        }

                        section("메모") {
                            TextField("도안에 관한 메모", text: $notes, axis: .vertical)
                                .lineLimit(4...8)
                                .padding(YDSpacing.x3)
                                .background(YDColor.cream0)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                                    .stroke(YDColor.line, lineWidth: 1)
                                }
                        }

                        fileInformation(pattern)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(YDColor.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(YDColor.danger.opacity(0.08))
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )
                        }

                        if !pattern.isSample {
                            Button("도안 삭제", role: .destructive) {
                                showsDeleteConfirmation = true
                            }
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(YDColor.danger)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(YDColor.danger.opacity(0.08))
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                        }
                    } else {
                        Text("도안 정보를 찾지 못했습니다.")
                            .foregroundStyle(YDColor.muted)
                            .padding(.vertical, YDSpacing.x8)
                    }
                }
                .padding(YDSpacing.x4)
            }
            .background(YDColor.cream1)
            .navigationTitle("도안 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                    .foregroundStyle(YDColor.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "저장 중" : "저장") {
                        save()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(YDColor.yarn4)
                    .disabled(pattern?.isSample != false || isSaving)
                }
            }
        }
        .task {
            loadPatternIfNeeded()
        }
        .alert("도안을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                deletePattern()
            }
        } message: {
            Text("원본 파일, 작업용 PDF, 표시와 마지막 페이지 정보도 함께 삭제됩니다.")
        }
    }

    private var pattern: PatternItem? {
        store.pattern(id: patternID)
    }

    private var readOnlyNotice: some View {
        Text("샘플 도안은 내용을 확인할 수 있지만 수정하거나 삭제할 수 없습니다.")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(YDColor.wood3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(YDColor.wood1.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: YDSpacing.x3) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(YDColor.ink)
            content()
        }
        .padding(YDSpacing.x4)
        .ydSurfaceCard()
        .disabled(pattern?.isSample == true)
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(YDColor.muted)
            content()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, YDSpacing.x3)
                .frame(minHeight: 46)
                .background(YDColor.cream0)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(YDColor.line, lineWidth: 1)
                }
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        field(title) {
            TextField("선택", text: text)
                .keyboardType(.decimalPad)
        }
    }

    private func fileInformation(_ pattern: PatternItem) -> some View {
        VStack(alignment: .leading, spacing: YDSpacing.x3) {
            Text("파일 정보")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(YDColor.ink)
            informationRow("파일명", pattern.originalFileName)
            informationRow("형식", pattern.sourceFileType.rawValue.uppercased())
            informationRow("페이지", "\(pattern.pageCount)쪽")
        }
        .padding(YDSpacing.x4)
        .ydSurfaceCard()
    }

    private func informationRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(YDColor.muted)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(YDColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadPatternIfNeeded() {
        guard !didLoad, let pattern else {
            return
        }
        didLoad = true
        title = pattern.title
        designerName = pattern.designerName ?? ""
        craftType = pattern.craftType
        tagsText = pattern.tags.joined(separator: ", ")
        gaugeStitches = pattern.gaugeInfo?.stitches.editText ?? ""
        gaugeRows = pattern.gaugeInfo?.rows.editText ?? ""
        gaugeLength = pattern.gaugeInfo?.measurementLengthCM.editText ?? ""
        yarnName = pattern.materialInfo?.yarnName ?? ""
        yarnWeight = pattern.materialInfo?.yarnWeight ?? ""
        needleSize = pattern.materialInfo?.needleSizeMM.editText ?? ""
        hookSize = pattern.materialInfo?.hookSizeMM.editText ?? ""
        notes = pattern.notes ?? ""
    }

    private func save() {
        guard var updatedPattern = pattern else {
            return
        }

        do {
            updatedPattern.title = title
            updatedPattern.designerName = designerName.nilIfBlank
            updatedPattern.craftType = craftType
            updatedPattern.tags = normalizedTags

            let gauge = PatternGaugeInfo(
                stitches: try number(gaugeStitches, label: "게이지 코 수"),
                rows: try number(gaugeRows, label: "게이지 단 수"),
                measurementLengthCM: try number(gaugeLength, label: "게이지 기준 길이")
            )
            updatedPattern.gaugeInfo = gauge.isEmpty ? nil : gauge

            let material = PatternMaterialInfo(
                yarnName: yarnName.nilIfBlank,
                yarnWeight: yarnWeight.nilIfBlank,
                needleSizeMM: try number(needleSize, label: "대바늘 크기"),
                hookSizeMM: try number(hookSize, label: "코바늘 크기")
            )
            updatedPattern.materialInfo = material.isEmpty ? nil : material
            updatedPattern.notes = notes.nilIfBlank

            isSaving = true
            errorMessage = nil
            Task {
                defer { isSaving = false }
                do {
                    try await store.updatePattern(updatedPattern)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePattern() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await store.deletePattern(patternID)
                dismiss()
                onDeleted()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var normalizedTags: [String] {
        var seen = Set<String>()
        return tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty && seen.insert($0.localizedLowercase).inserted
            }
            .prefix(10)
            .map { $0 }
    }

    private func number(_ value: String, label: String) throws -> Double? {
        guard let trimmed = value.nilIfBlank else {
            return nil
        }
        guard
            let result = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
            result > 0
        else {
            throw PatternDetailsError.invalidNumber(label)
        }
        return result
    }
}

private enum PatternDetailsError: LocalizedError {
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .invalidNumber(let label):
            "\(label)은 0보다 큰 숫자로 입력해 주세요."
        }
    }
}

private extension Optional where Wrapped == Double {
    var editText: String? {
        guard let value = self else {
            return nil
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
