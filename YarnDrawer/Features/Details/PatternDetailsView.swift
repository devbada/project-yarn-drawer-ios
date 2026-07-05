import SwiftUI
import UniformTypeIdentifiers

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
    @State private var fiberContent = ""
    @State private var yarnAmount = ""
    @State private var yarnColor = ""
    @State private var needleSize = ""
    @State private var hookSize = ""
    @State private var notes = ""
    @State private var progress = 0.0
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var showsReconnectPicker = false
    @State private var isSaving = false
    @State private var didLoad = false
    @State private var invalidFields = Set<DetailsValidationField>()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    if let pattern {
                        if pattern.isSample {
                            readOnlyNotice
                        }

                        section("기본 정보") {
                            field(
                                "도안명",
                                isInvalid: invalidFields.contains(.title) && !isTitleValid,
                                message: "도안명을 입력해 주세요."
                            ) {
                                TextField("필수", text: $title)
                            }
                            field(
                                "작가명",
                                isInvalid: invalidFields.contains(.designerName) && !isDesignerNameValid,
                                message: "작가명은 100자 이하로 입력해 주세요."
                            ) {
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
                            field("섬유") {
                                TextField("예: 메리노 100%", text: $fiberContent)
                            }
                            field("사용량") {
                                TextField("예: 3볼(450g)", text: $yarnAmount)
                            }
                            field("색상") {
                                TextField("예: 네이비", text: $yarnColor)
                            }
                            HStack(spacing: YDSpacing.x2) {
                                numberField("대바늘 mm", text: $needleSize)
                                numberField("코바늘 mm", text: $hookSize)
                            }
                        }

                        section("진행률") {
                            VStack(alignment: .leading, spacing: YDSpacing.x3) {
                                HStack {
                                    Text(progress >= 1 ? "완료" : "\(Int(progress * 100))%")
                                        .font(YDFont.font(size: 22, weight: .heavy))
                                        .foregroundStyle(YDColor.yarn4)
                                    Spacer()
                                    Text("카드 진행 막대에 반영")
                                        .font(YDFont.font(size: 12, weight: .bold))
                                        .foregroundStyle(YDColor.muted)
                                }

                                Slider(value: $progress, in: 0...1, step: 0.01)
                                    .tint(YDColor.yarn4)
                                    .accessibilityLabel("진행률")
                                    .accessibilityValue("\(Int(progress * 100))%")

                                HStack(spacing: YDSpacing.x2) {
                                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                                        Button(value >= 1 ? "완료" : "\(Int(value * 100))%") {
                                            progress = value
                                        }
                                        .font(YDFont.font(size: 12, weight: .bold))
                                        .foregroundStyle(progress == value ? YDColor.cream0 : YDColor.muted)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 34)
                                        .background(progress == value ? YDColor.ink : YDColor.cream0)
                                        .clipShape(Capsule())
                                        .overlay {
                                            Capsule()
                                                .stroke(YDColor.line, lineWidth: 1)
                                        }
                                    }
                                }
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
                                .font(YDFont.font(size: 13))
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

                        Button(pattern.isSample ? "샘플 도안 삭제" : "도안 삭제", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .font(YDFont.font(size: 14, weight: .heavy))
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
                    .font(YDFont.font(size: 17, weight: .bold))
                    .foregroundStyle(YDColor.yarn4)
                    .disabled(pattern?.isSample != false || isSaving)
                }
            }
        }
        .task {
            loadPatternIfNeeded()
        }
        .alert(deleteTitle, isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                deletePattern()
            }
        } message: {
            Text(deleteMessage)
        }
        .sheet(isPresented: $showsReconnectPicker) {
            PatternReconnectDocumentPicker(
                allowedContentTypes: [.pdf, .jpeg, .png],
                onPick: reconnectFile,
                onFailure: {
                    errorMessage = "파일을 다시 선택하지 못했습니다."
                }
            )
        }
    }

    private var pattern: PatternItem? {
        store.pattern(id: patternID)
    }

    private var readOnlyNotice: some View {
        Text("샘플 도안은 수정할 수 없지만 보관함에서 삭제할 수 있습니다.")
            .font(YDFont.font(size: 13, weight: .bold))
            .foregroundStyle(YDColor.wood3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(YDColor.wood1.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var deleteTitle: String {
        pattern?.isSample == true ? "샘플 도안을 삭제할까요?" : "도안을 삭제할까요?"
    }

    private var deleteMessage: String {
        if pattern?.isSample == true {
            return "샘플 도안이 보관함에서 숨겨집니다. 직접 등록한 도안에는 영향 없습니다."
        }
        return "원본 파일, 작업용 PDF, 표시와 마지막 페이지 정보도 함께 삭제됩니다."
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: YDSpacing.x3) {
            Text(title)
                .font(YDFont.font(size: 15, weight: .heavy))
                .foregroundStyle(YDColor.ink)
            content()
        }
        .padding(YDSpacing.x4)
        .ydSurfaceCard()
        .disabled(pattern?.isSample == true)
    }

    private func field<Content: View>(
        _ title: String,
        isInvalid: Bool = false,
        message: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: YDSpacing.x2) {
                Text(title)
                    .font(YDFont.font(size: 12, weight: .heavy))
                    .foregroundStyle(isInvalid ? YDColor.danger : YDColor.muted)
                if isInvalid, let message {
                    Text(message)
                        .font(YDFont.font(size: 12, weight: .bold))
                        .foregroundStyle(YDColor.danger)
                }
            }
            content()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, YDSpacing.x3)
                .frame(minHeight: 46)
                .background(isInvalid ? YDColor.danger.opacity(0.06) : YDColor.cream0)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(isInvalid ? YDColor.danger : YDColor.line, lineWidth: isInvalid ? 2 : 1)
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
                .font(YDFont.font(size: 15, weight: .heavy))
                .foregroundStyle(YDColor.ink)
            informationRow("파일명", pattern.originalFileName)
            informationRow("형식", pattern.sourceFileType.rawValue.uppercased())
            informationRow("페이지", "\(pattern.pageCount)쪽")
            informationRow("등록일", pattern.createdAt.formatted(date: .abbreviated, time: .omitted))
            informationRow("수정일", pattern.updatedAt.formatted(date: .abbreviated, time: .omitted))
            if store.missingFilePatternIDs.contains(pattern.id) {
                Text("원본 또는 작업용 PDF 파일이 누락되었습니다.")
                    .font(YDFont.font(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, YDSpacing.x1)
            } else if store.checksumMismatchPatternIDs.contains(pattern.id) {
                Text("저장된 파일 checksum이 등록 시점과 다릅니다. 파일을 다시 선택해 복구할 수 있습니다.")
                    .font(YDFont.font(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, YDSpacing.x1)
            }
            if !pattern.isSample {
                Button("파일 다시 선택") {
                    showsReconnectPicker = true
                }
                .font(YDFont.font(size: 13, weight: .heavy))
                .foregroundStyle(YDColor.yarn4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
                .background(YDColor.surfaceGreen)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.top, YDSpacing.x2)
            }
        }
        .padding(YDSpacing.x4)
        .ydSurfaceCard()
    }

    private func informationRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(YDFont.font(size: 12, weight: .bold))
                .foregroundStyle(YDColor.muted)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(YDFont.font(size: 13))
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
        fiberContent = pattern.materialInfo?.fiberContent ?? ""
        yarnAmount = pattern.materialInfo?.yarnAmount ?? ""
        yarnColor = pattern.materialInfo?.yarnColor ?? ""
        needleSize = pattern.materialInfo?.needleSizeMM.editText ?? ""
        hookSize = pattern.materialInfo?.hookSizeMM.editText ?? ""
        notes = pattern.notes ?? ""
        progress = min(max(pattern.progress, 0), 1)
    }

    private func save() {
        guard var updatedPattern = pattern else {
            return
        }

        invalidFields = validationFields()
        guard invalidFields.isEmpty else {
            errorMessage = "필수 정보를 입력해 주세요."
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
                fiberContent: fiberContent.nilIfBlank,
                yarnAmount: yarnAmount.nilIfBlank,
                yarnColor: yarnColor.nilIfBlank,
                needleSizeMM: try number(needleSize, label: "대바늘 크기"),
                hookSizeMM: try number(hookSize, label: "코바늘 크기")
            )
            updatedPattern.materialInfo = material.isEmpty ? nil : material
            updatedPattern.notes = notes.nilIfBlank
            updatedPattern.progress = min(max(progress, 0), 1)

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

    private func validationFields() -> Set<DetailsValidationField> {
        var fields = Set<DetailsValidationField>()
        if !isTitleValid {
            fields.insert(.title)
        }
        if !isDesignerNameValid {
            fields.insert(.designerName)
        }
        return fields
    }

    private var isTitleValid: Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedTitle.isEmpty && normalizedTitle.count <= 100
    }

    private var isDesignerNameValid: Bool {
        designerName.count <= 100
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

    private func reconnectFile(_ url: URL) {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await store.reconnectPatternFile(sourceURL: url, for: patternID)
                didLoad = false
                loadPatternIfNeeded()
                errorMessage = nil
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

private enum DetailsValidationField {
    case title
    case designerName
}

struct PatternReconnectDocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onFailure: () -> Void

        init(
            onPick: @escaping (URL) -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onFailure = onFailure
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                onFailure()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
