import SwiftUI

private enum PatternTool: String, CaseIterable, Identifiable {
    case highlight
    case eraser
    case check
    case note
    case currentRow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlight: "형광펜"
        case .eraser: "지우개"
        case .check: "체크"
        case .note: "메모"
        case .currentRow: "현재 줄"
        }
    }

    var icon: YDIcon? {
        switch self {
        case .highlight: .highlight
        case .eraser: nil
        case .check: .check
        case .note: .note
        case .currentRow: .row
        }
    }
}

private enum ViewerSheet: String, Identifiable {
    case more
    case symbols
    case gauge
    case details

    var id: String { rawValue }
}

private enum ProtectedAction {
    case close
    case showOriginal
}

struct PatternViewerView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.dismiss) private var dismiss
    let pattern: PatternItem

    @State private var selectedTool: PatternTool = .check
    @State private var isOriginalMode = false
    @State private var isDirty = false
    @State private var activeSheet: ViewerSheet?
    @State private var protectedAction: ProtectedAction?
    @State private var showsUnsavedAlert = false
    @State private var viewURL: URL?
    @State private var isDocumentLoading = true
    @State private var toastMessage: String?
    @State private var annotations: [PatternAnnotation] = []
    @State private var pendingAnnotationSaveCount = 0
    @State private var annotationSaveFailed = false
    @State private var initialPageIndex = 0
    @State private var initialProgress: Double?
    @State private var lastSavedPageIndex = -1
    @State private var editingNote: PatternAnnotation?
    @State private var noteText = ""
    @State private var showsNoteEditor = false
    @State private var undoStack: [[PatternAnnotation]] = []
    @State private var redoStack: [[PatternAnnotation]] = []
    @State private var selectedHighlightHex = HighlightInk.presets[0].hex
    @State private var customHighlightColor = Color(hex: 0xF9A8D4)
    @AppStorage("viewerSelectedTool")
    private var storedSelectedTool = PatternTool.check.rawValue
    @AppStorage("viewerSelectedHighlightHex")
    private var storedSelectedHighlightHex = HighlightInk.presets[0].hex
    @AppStorage("highlightFavoriteHexes")
    private var highlightFavoriteHexes = ""

    var body: some View {
        ZStack {
            Color(hex: 0xDED5C4).ignoresSafeArea()

            VStack(spacing: 0) {
                viewerTopBar
                documentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if selectedTool == .highlight && !isOriginalMode {
                    highlightColorPicker
                }
                viewerToolbar
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        activeSheet = .symbols
                    } label: {
                        YDIconView(icon: .star, size: 24)
                            .foregroundStyle(YDColor.wood1)
                            .frame(width: 54, height: 54)
                            .background(YDColor.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: YDColor.wood3.opacity(0.14), radius: 20, y: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("현재 도안 기호 열기")
                }
                .padding(.trailing, 14)
                .padding(.bottom, 88)
            }

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(YDColor.cream0)
                        .padding(.horizontal, YDSpacing.x4)
                        .padding(.vertical, YDSpacing.x3)
                        .background(YDColor.ink.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.bottom, 94)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            restoreViewerToolPreferences()
        }
        .onChange(of: selectedTool) { _, tool in
            storedSelectedTool = tool.rawValue
        }
        .onChange(of: selectedHighlightHex) { _, hex in
            storedSelectedHighlightHex = hex
        }
        .task {
            isDocumentLoading = !pattern.isSample
            do {
                let savedPageIndex = try await store.viewerState(for: pattern.id)?
                    .lastPageIndex
                annotations = try await store.annotations(for: pattern.id)
                if let restoredProgress {
                    initialPageIndex = 0
                    initialProgress = restoredProgress
                } else {
                    initialPageIndex = savedPageIndex ?? 0
                    initialProgress = nil
                }
            } catch {
                annotationSaveFailed = true
                showToast("저장된 작업 상태를 불러오지 못했습니다.")
            }
            viewURL = await store.viewURL(for: pattern)
            isDocumentLoading = false
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .more:
                viewerToolsSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .symbols:
                CurrentPatternSymbolsView(patternTitle: pattern.title)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .gauge:
                GaugeCalculatorView()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .details:
                PatternDetailsView(patternID: pattern.id) {
                    dismiss()
                }
            }
        }
        .alert("변경사항이 있습니다", isPresented: $showsUnsavedAlert) {
            Button("계속 편집", role: .cancel) {
                protectedAction = nil
            }
            Button("저장 후 계속") {
                saveAnnotationsAndPerformProtectedAction()
            }
        } message: {
            Text("현재 작업을 저장한 뒤 요청한 동작을 계속합니다.")
        }
        .alert("메모", isPresented: $showsNoteEditor) {
            TextField("메모 내용", text: $noteText)
            Button("취소", role: .cancel) {
                clearEditingNote()
            }
            if isEditingExistingNote {
                Button("삭제", role: .destructive) {
                    deleteEditingNote()
                }
            }
            Button("저장") {
                saveEditingNote()
            }
        } message: {
            Text("선택한 위치에 메모를 저장합니다.")
        }
    }

    private var viewerTopBar: some View {
        HStack(spacing: 10) {
            YDIconButton(icon: .back, accessibilityLabel: "보관함으로 돌아가기") {
                requestClose()
            }
            Spacer()
            VStack(spacing: 2) {
                Text(store.pattern(id: pattern.id)?.title ?? pattern.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                    .lineLimit(1)
                Text(viewerStatus)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(YDColor.yarn4)
                    .accessibilityLabel(viewerStatus)
            }
            Spacer()
            YDIconButton(icon: .more, accessibilityLabel: "도안 도구") {
                activeSheet = .more
            }
        }
        .padding(.horizontal, YDSpacing.x3)
        .padding(.vertical, YDSpacing.x2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YDColor.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private var documentArea: some View {
        if let viewURL {
            PDFKitView(
                url: viewURL,
                annotations: annotations,
                annotationTool: activePDFAnnotationTool,
                showsAnnotations: !isOriginalMode,
                allowsTextSelection: isOriginalMode,
                highlightHex: selectedHighlightHex,
                initialPageIndex: initialPageIndex,
                initialProgress: initialProgress,
                onAnnotationCreated: addAnnotation,
                onAnnotationDeleted: { deleteAnnotation($0) },
                onAnnotationMoved: moveAnnotation,
                onNoteRequested: beginEditingNote,
                onPageChanged: saveCurrentPage
            )
                .overlay(alignment: .top) {
                    if isOriginalMode {
                        Text("원본 보기 · 표시 도구 잠김")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YDColor.ink)
                            .padding(.horizontal, YDSpacing.x3)
                            .padding(.vertical, YDSpacing.x2)
                            .background(YDColor.wood1)
                            .clipShape(Capsule())
                            .padding(.top, YDSpacing.x3)
                    } else if selectedTool == .highlight {
                        Text("한 손가락 드래그: 형광펜 · 두 손가락 드래그: 이동")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(YDColor.ink)
                            .padding(.horizontal, YDSpacing.x3)
                            .padding(.vertical, YDSpacing.x2)
                            .background(YDColor.wood1.opacity(0.94))
                            .clipShape(Capsule())
                            .padding(.top, YDSpacing.x3)
                    } else if selectedTool == .check {
                        Text("탭: 체크 · 길게 누름: 선택 후 이동")
                            .viewerGuideStyle()
                    } else if selectedTool == .eraser {
                        Text("지울 표시를 누르세요.")
                            .viewerGuideStyle()
                    } else if selectedTool == .note {
                        Text("탭: 메모 · 길게 누름: 선택 후 이동")
                            .viewerGuideStyle()
                    } else if selectedTool == .currentRow {
                        Text("탭: 현재 줄 · 길게 누름: 선택 후 이동")
                            .viewerGuideStyle()
                    }
                }
        } else if pattern.isSample {
            SamplePatternPaper(
                selectedTool: selectedTool,
                isOriginalMode: isOriginalMode,
                onChanged: {
                    isDirty = true
                    showToast(toolResultMessage)
                }
            )
        } else if isDocumentLoading {
            DocumentLoadingView()
        } else {
            MissingDocumentView()
        }
    }

    private var viewerToolbar: some View {
        HStack(spacing: 5) {
            ForEach(PatternTool.allCases) { tool in
                Button {
                    selectedTool = tool
                    if tool == .highlight {
                        showToast("PDF 위를 한 손가락으로 드래그해 표시하세요.")
                    } else if tool == .eraser {
                        showToast("지울 표시를 누르세요.")
                    } else if tool == .check {
                        showToast("완료한 위치를 눌러 체크하세요.")
                    } else if tool == .note {
                        showToast("메모를 남길 위치를 누르세요.")
                    } else if tool == .currentRow {
                        showToast("현재 작업 중인 줄을 누르세요.")
                    }
                } label: {
                    VStack(spacing: 3) {
                        toolIcon(tool)
                        Text(tool.title)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(selectedTool == tool ? YDColor.yarn4 : YDColor.muted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .background(selectedTool == tool ? YDColor.surfaceGreen : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isOriginalMode)
                .opacity(isOriginalMode ? 0.42 : 1)
                .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
            }

            Button {
                activeSheet = .more
            } label: {
                VStack(spacing: 3) {
                    YDIconView(icon: .more, size: 22)
                    Text("더보기")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(YDColor.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, YDSpacing.x2)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(YDColor.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private func toolIcon(_ tool: PatternTool) -> some View {
        if let icon = tool.icon {
            YDIconView(icon: icon, size: 22)
        } else {
            Image(systemName: "eraser")
                .font(.system(size: 19, weight: .bold))
                .frame(width: 22, height: 22)
        }
    }

    private var highlightColorPicker: some View {
        VStack(spacing: 2) {
            HStack(spacing: YDSpacing.x2) {
                Text("형광펜 팔레트")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.muted)
                Button {
                    undoLastHighlight()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("실행 취소")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(hasHighlightAnnotations ? YDColor.yarn4 : YDColor.muted)
                    .frame(minHeight: YDLayout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .disabled(!hasHighlightAnnotations)
                Spacer()
                ColorPicker(
                    "사용자 색상",
                    selection: $customHighlightColor,
                    supportsOpacity: false
                )
                .labelsHidden()
                .onChange(of: customHighlightColor) { _, color in
                    selectedHighlightHex = color.highlightHex
                }
                Button {
                    addFavoriteHighlightColor()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("즐겨찾기")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.yarn4)
                    .frame(minHeight: YDLayout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YDSpacing.x2) {
                    ForEach(paletteColors) { ink in
                        highlightSwatch(ink)
                    }
                }
                .padding(.horizontal, 3)
            }
        }
        .padding(.horizontal, YDSpacing.x4)
        .padding(.vertical, YDSpacing.x2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(YDColor.line).frame(height: 1)
        }
    }

    private func highlightSwatch(_ ink: HighlightInk) -> some View {
        Button {
            selectedHighlightHex = ink.hex
            customHighlightColor = Color(highlightHex: ink.hex)
            showToast("\(ink.title) 형광펜을 선택했습니다.")
        } label: {
            Circle()
                .fill(Color(highlightHex: ink.hex))
                .frame(width: 28, height: 28)
                .overlay {
                    if selectedHighlightHex == ink.hex {
                        Circle()
                            .stroke(YDColor.ink, lineWidth: 2)
                            .padding(-3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if favoriteHighlightColors.contains(where: { $0.hex == ink.hex }) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(YDColor.wood3)
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(
                    width: YDLayout.minimumTouchTarget,
                    height: YDLayout.minimumTouchTarget
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ink.title) 형광펜")
        .accessibilityAddTraits(selectedHighlightHex == ink.hex ? .isSelected : [])
        .contextMenu {
            if favoriteHighlightColors.contains(where: { $0.hex == ink.hex }) {
                Button("즐겨찾기에서 제거", role: .destructive) {
                    removeFavoriteHighlightColor(ink.hex)
                }
            }
        }
    }

    private var favoriteHighlightColors: [HighlightInk] {
        highlightFavoriteHexes
            .split(separator: ",")
            .map(String.init)
            .filter { $0.count == 6 }
            .map { HighlightInk(hex: $0, title: "즐겨찾기") }
    }

    private var paletteColors: [HighlightInk] {
        var seen = Set<String>()
        return (favoriteHighlightColors + HighlightInk.presets).filter {
            seen.insert($0.hex).inserted
        }
    }

    private var hasHighlightAnnotations: Bool {
        annotations.contains { $0.type == .highlight }
    }

    private func undoLastHighlight() {
        guard
            let annotation = annotations
                .filter({ $0.type == .highlight })
                .max(by: { $0.createdAt < $1.createdAt })
        else {
            showToast("되돌릴 형광펜 표시가 없습니다.")
            return
        }
        deleteAnnotation(annotation, successMessage: "마지막 형광펜 표시를 되돌렸습니다.")
    }

    private func addFavoriteHighlightColor() {
        let hex = customHighlightColor.highlightHex
        var values = highlightFavoriteHexes
            .split(separator: ",")
            .map(String.init)
        guard !values.contains(hex) else {
            selectedHighlightHex = hex
            showToast("이미 즐겨찾는 색상입니다.")
            return
        }
        values.insert(hex, at: 0)
        highlightFavoriteHexes = values.prefix(12).joined(separator: ",")
        selectedHighlightHex = hex
        showToast("색상을 즐겨찾기에 추가했습니다.")
    }

    private func removeFavoriteHighlightColor(_ hex: String) {
        highlightFavoriteHexes = highlightFavoriteHexes
            .split(separator: ",")
            .map(String.init)
            .filter { $0 != hex }
            .joined(separator: ",")
    }

    private var viewerToolsSheet: some View {
        NavigationStack {
            VStack(spacing: 9) {
                HStack(spacing: YDSpacing.x2) {
                    historyButton(
                        title: "실행 취소",
                        systemImage: "arrow.uturn.backward",
                        isEnabled: !undoStack.isEmpty,
                        action: undoAnnotationChange
                    )
                    historyButton(
                        title: "다시 실행",
                        systemImage: "arrow.uturn.forward",
                        isEnabled: !redoStack.isEmpty,
                        action: redoAnnotationChange
                    )
                }
                sheetAction(
                    title: isOriginalMode ? "편집본으로 돌아가기" : "원본 보기",
                    description: isOriginalMode
                        ? "작업 표시와 현재 줄 복원"
                        : "표시 없는 원본 파일 확인"
                ) {
                    activeSheet = nil
                    requestOriginalToggle()
                }
                sheetAction(
                    title: "게이지 계산기",
                    description: "목표 길이에 필요한 코·단 계산"
                ) {
                    activeSheet = .gauge
                }
                sheetAction(
                    title: "상세정보",
                    description: "도안, 실, 바늘, 파일 정보"
                ) {
                    activeSheet = .details
                }
                Spacer()
            }
            .padding(YDSpacing.x4)
            .background(YDColor.cream0)
            .navigationTitle("도안 도구")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func historyButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isEnabled ? YDColor.yarn4 : YDColor.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(isEnabled ? YDColor.surfaceGreen : YDColor.cream2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(YDColor.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func sheetAction(
        title: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(YDColor.ink)
                Spacer()
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(YDColor.muted)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .background(YDColor.cream0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(YDColor.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var viewerStatus: String {
        if isOriginalMode {
            return "원본 보기 · 편집 도구 잠김"
        }
        if pendingAnnotationSaveCount > 0 {
            return "편집 상태 · 자동 저장 중"
        }
        if annotationSaveFailed {
            return "편집 상태 · 저장 실패"
        }
        return isDirty ? "편집 상태 · 변경사항 있음" : "편집 상태 · 저장됨"
    }

    private var activePDFAnnotationTool: PDFAnnotationTool? {
        guard !isOriginalMode else {
            return nil
        }
        return switch selectedTool {
        case .highlight: .highlight
        case .eraser: .eraser
        case .check: .check
        case .currentRow: .currentRow
        case .note: .note
        }
    }

    private var restoredProgress: Double? {
        let progress = latestCheckProgress ?? pattern.progress
        guard progress > 0 else {
            return nil
        }
        return min(max(progress, 0), 1)
    }

    private var latestCheckProgress: Double? {
        guard pattern.pageCount > 0 else {
            return nil
        }
        return latestCheckAnnotation.map {
            progress(for: $0)
        }
    }

    private var latestCheckAnnotation: PatternAnnotation? {
        annotations
            .filter { $0.type == .check }
            .max { $0.createdAt < $1.createdAt }
    }

    private func progress(for annotation: PatternAnnotation) -> Double {
        let pageCount = max(1, pattern.pageCount)
        let pageProgress = min(
            max(1 - annotation.bounds.centerY, 0),
            1
        )
        let rawProgress = (
            Double(annotation.pageIndex) + pageProgress
        ) / Double(pageCount)
        return min(max(rawProgress, 0), 1)
    }

    private var toolResultMessage: String {
        switch selectedTool {
        case .highlight: "형광펜 표시를 변경했습니다."
        case .eraser: "표시를 지웠습니다."
        case .check: "완료 체크를 변경했습니다."
        case .note: "메모를 변경했습니다."
        case .currentRow: "현재 작업 줄을 옮겼습니다."
        }
    }

    private func requestClose() {
        guard isDirty else {
            dismiss()
            return
        }
        protectedAction = .close
        showsUnsavedAlert = true
    }

    private func requestOriginalToggle() {
        if isOriginalMode {
            isOriginalMode = false
            return
        }
        guard isDirty else {
            isOriginalMode = true
            return
        }
        protectedAction = .showOriginal
        showsUnsavedAlert = true
    }

    private func performProtectedAction() {
        switch protectedAction {
        case .close:
            dismiss()
        case .showOriginal:
            isOriginalMode = true
        case .none:
            break
        }
        protectedAction = nil
    }

    private func restoreViewerToolPreferences() {
        selectedTool = PatternTool(rawValue: storedSelectedTool) ?? .check
        let hex = String(storedSelectedHighlightHex.filter(\.isHexDigit).prefix(6)).uppercased()
        guard hex.count == 6 else {
            return
        }
        selectedHighlightHex = hex
        customHighlightColor = Color(highlightHex: hex)
    }

    private func recordAnnotationHistory() {
        undoStack.append(annotations)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func undoAnnotationChange() {
        guard let previousAnnotations = undoStack.popLast() else {
            showToast("되돌릴 작업이 없습니다.")
            return
        }
        redoStack.append(annotations)
        annotations = previousAnnotations
        saveAnnotationSnapshot(
            successMessage: "이전 작업으로 되돌렸습니다.",
            failureMessage: "실행 취소를 저장하지 못했습니다.",
            startedMessage: "실행 취소를 저장합니다.",
            updatesProgress: true
        )
    }

    private func redoAnnotationChange() {
        guard let nextAnnotations = redoStack.popLast() else {
            showToast("다시 실행할 작업이 없습니다.")
            return
        }
        undoStack.append(annotations)
        annotations = nextAnnotations
        saveAnnotationSnapshot(
            successMessage: "작업을 다시 실행했습니다.",
            failureMessage: "다시 실행을 저장하지 못했습니다.",
            startedMessage: "다시 실행을 저장합니다.",
            updatesProgress: true
        )
    }

    private func addAnnotation(_ annotation: PatternAnnotation) {
        recordAnnotationHistory()
        if annotation.type == .currentRow {
            annotations.removeAll { $0.type == .currentRow }
        }
        annotations.append(annotation)
        isDirty = true
        annotationSaveFailed = false
        pendingAnnotationSaveCount += 1
        showToast("\(annotation.type.saveTitle)을 자동 저장합니다.")

        Task {
            do {
                if annotation.type == .currentRow {
                    try await store.saveAnnotations(annotations, for: pattern.id)
                } else {
                    try await store.addAnnotation(annotation, to: pattern.id)
                }
                if annotation.type == .check {
                    try await store.updateProgress(progress(for: annotation), for: pattern.id)
                }
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast("\(annotation.type.saveTitle)을 저장했습니다.")
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast("\(annotation.type.saveTitle)을 저장하지 못했습니다.")
            }
        }
    }

    private func deleteAnnotation(
        _ annotation: PatternAnnotation,
        successMessage: String? = nil
    ) {
        recordAnnotationHistory()
        annotations.removeAll { $0.id == annotation.id }
        isDirty = true
        annotationSaveFailed = false
        pendingAnnotationSaveCount += 1
        showToast("\(annotation.type.saveTitle)을 삭제합니다.")

        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                if annotation.type == .check {
                    try await store.updateProgress(latestCheckProgress ?? 0, for: pattern.id)
                }
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast(successMessage ?? "\(annotation.type.saveTitle)을 삭제했습니다.")
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast("\(annotation.type.saveTitle)을 삭제하지 못했습니다.")
            }
        }
    }

    private func moveAnnotation(_ annotation: PatternAnnotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return
        }
        recordAnnotationHistory()
        annotations[index] = annotation
        isDirty = true
        annotationSaveFailed = false
        pendingAnnotationSaveCount += 1
        showToast("\(annotation.type.saveTitle)을 이동합니다.")

        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                if annotation.type == .check {
                    try await store.updateProgress(progress(for: annotation), for: pattern.id)
                }
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast("\(annotation.type.saveTitle)을 이동했습니다.")
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast("\(annotation.type.saveTitle)을 이동하지 못했습니다.")
            }
        }
    }

    private var isEditingExistingNote: Bool {
        guard let editingNote else {
            return false
        }
        return annotations.contains { $0.id == editingNote.id }
    }

    private func beginEditingNote(_ annotation: PatternAnnotation) {
        editingNote = annotation
        noteText = annotation.noteText ?? ""
        showsNoteEditor = true
    }

    private func clearEditingNote() {
        editingNote = nil
        noteText = ""
    }

    private func saveEditingNote() {
        guard var note = editingNote else {
            return
        }
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            showToast("메모 내용을 입력해 주세요.")
            return
        }

        recordAnnotationHistory()
        note.noteText = trimmedText
        if let index = annotations.firstIndex(where: { $0.id == note.id }) {
            annotations[index] = note
        } else {
            annotations.append(note)
        }
        clearEditingNote()
        saveAnnotationSnapshot(
            successMessage: "메모를 저장했습니다.",
            failureMessage: "메모를 저장하지 못했습니다.",
            startedMessage: "메모를 자동 저장합니다."
        )
    }

    private func deleteEditingNote() {
        guard let note = editingNote else {
            return
        }
        clearEditingNote()
        deleteAnnotation(note)
    }

    private func saveAnnotationSnapshot(
        successMessage: String,
        failureMessage: String,
        startedMessage: String,
        updatesProgress: Bool = false
    ) {
        isDirty = true
        annotationSaveFailed = false
        pendingAnnotationSaveCount += 1
        showToast(startedMessage)

        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                if updatesProgress {
                    try await store.updateProgress(latestCheckProgress ?? 0, for: pattern.id)
                }
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast(successMessage)
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast(failureMessage)
            }
        }
    }

    private func saveCurrentPage(_ pageIndex: Int) {
        guard pageIndex != lastSavedPageIndex else {
            return
        }
        lastSavedPageIndex = pageIndex
        Task {
            try? await store.saveViewerPage(pageIndex, for: pattern.id)
        }
    }

    private func saveAnnotationsAndPerformProtectedAction() {
        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                pendingAnnotationSaveCount = 0
                annotationSaveFailed = false
                isDirty = false
                performProtectedAction()
            } catch {
                annotationSaveFailed = true
                isDirty = true
                showToast("형광펜 표시를 저장하지 못했습니다.")
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    toastMessage = nil
                }
            }
        }
    }
}

private extension PatternAnnotationType {
    var saveTitle: String {
        switch self {
        case .highlight: "형광펜 표시"
        case .check: "체크"
        case .note: "메모"
        case .currentRow: "현재 줄"
        }
    }
}

private extension View {
    func viewerGuideStyle() -> some View {
        font(.system(size: 12, weight: .bold))
            .foregroundStyle(YDColor.ink)
            .padding(.horizontal, YDSpacing.x3)
            .padding(.vertical, YDSpacing.x2)
            .background(YDColor.wood1.opacity(0.94))
            .clipShape(Capsule())
            .padding(.top, YDSpacing.x3)
    }
}

private extension Color {
    init(highlightHex hex: String) {
        let sanitized = String(hex.filter(\.isHexDigit).prefix(6))
        let value = UInt32(sanitized, radix: 16) ?? 0xF1C878
        self.init(hex: value)
    }

    var highlightHex: String {
        let resolved = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "F1C878"
        }
        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

private struct SamplePatternLine: Identifiable {
    let id = UUID()
    let text: String
    var checked = false
    var highlighted = false
    var current = false
}

private struct DocumentLoadingView: View {
    var body: some View {
        VStack(spacing: YDSpacing.x3) {
            ProgressView()
                .tint(YDColor.yarn4)
            Text("도안을 여는 중입니다.")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(YDColor.ink)
            Text("저장된 페이지와 표시를 복원하고 있습니다.")
                .font(.system(size: 12))
                .foregroundStyle(YDColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xDED5C4))
    }
}

private struct MissingDocumentView: View {
    var body: some View {
        VStack(spacing: YDSpacing.x3) {
            YDIconView(icon: .storage, size: 34)
                .foregroundStyle(YDColor.wood3)
            Text("작업용 PDF를 열 수 없습니다.")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(YDColor.ink)
            Text("파일 누락 감지와 재연결은 남은 구현 항목입니다.")
                .font(.system(size: 12))
                .foregroundStyle(YDColor.muted)
        }
        .padding(YDSpacing.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xDED5C4))
    }
}

private struct SamplePatternPaper: View {
    let selectedTool: PatternTool
    let isOriginalMode: Bool
    let onChanged: () -> Void
    @State private var lines = [
        SamplePatternLine(text: "1단: 겉뜨기 106코", checked: true),
        SamplePatternLine(text: "2단: 안뜨기 106코", checked: true),
        SamplePatternLine(text: "3단: 양 끝 5코 고무뜨기, 중앙 무늬 반복", current: true),
        SamplePatternLine(text: "4단: 무늬대로 뜨기"),
        SamplePatternLine(text: "5단: 12코마다 바늘비우기 1회"),
        SamplePatternLine(text: "6단: 안뜨기, 바늘비우기 코 포함"),
        SamplePatternLine(text: "7단: 암홀 시작 전까지 8회 반복")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("몸판 뜨기")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(YDColor.ink)

                VStack(alignment: .leading, spacing: YDSpacing.x4) {
                    ForEach(lines.indices, id: \.self) { index in
                        Button {
                            applyTool(at: index)
                        } label: {
                            HStack(alignment: .top, spacing: 4) {
                                if lines[index].checked && !isOriginalMode {
                                    Text("✓")
                                        .fontWeight(.black)
                                        .foregroundStyle(YDColor.yarn4)
                                }
                                Text(lines[index].text)
                                    .foregroundStyle(Color(hex: 0x4F473B))
                                    .multilineTextAlignment(.leading)
                            }
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background {
                                if !isOriginalMode && lines[index].current {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(YDColor.currentRow)
                                } else if !isOriginalMode && lines[index].highlighted {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(YDColor.highlight)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isOriginalMode)
                    }
                }
            }
            .padding(.horizontal, YDSpacing.x8)
            .padding(.vertical, 44)
            .frame(maxWidth: 760, minHeight: 780, alignment: .topLeading)
            .background(YDColor.cream0)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: 0xD5C5A6), lineWidth: 1)
            }
            .shadow(color: Color(hex: 0x392B19).opacity(0.16), radius: 25, y: 12)
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .background(isOriginalMode ? Color(hex: 0xD3CBBD) : Color(hex: 0xDED5C4))
    }

    private func applyTool(at index: Int) {
        guard !isOriginalMode else { return }
        switch selectedTool {
        case .highlight:
            lines[index].highlighted.toggle()
        case .eraser:
            lines[index].highlighted = false
            lines[index].checked = false
            lines[index].current = false
        case .check:
            lines[index].checked.toggle()
        case .note:
            return
        case .currentRow:
            for lineIndex in lines.indices {
                lines[lineIndex].current = lineIndex == index
            }
        }
        onChanged()
    }
}

private struct CurrentPatternSymbolsView: View {
    let patternTitle: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: YDSpacing.x3) {
                    Text("\(patternTitle) 전용 기호를 먼저 표시합니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(YDColor.yarn4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(YDColor.surfaceGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    symbolRow(glyph: "V", name: "중앙 두 코 늘리기", metadata: "도안 전용 · 3단 반복")
                    symbolRow(glyph: "○", name: "바늘비우기", metadata: "공통 기호 · yo")
                }
                .padding(YDSpacing.x4)
            }
            .background(YDColor.cream0)
            .navigationTitle("현재 도안 기호")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func symbolRow(glyph: String, name: String, metadata: String) -> some View {
        HStack(spacing: 11) {
            Text(glyph)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(YDColor.yarn4)
                .frame(width: 48, height: 48)
                .background(YDColor.surfaceGreen)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                Text(metadata)
                    .font(.system(size: 12))
                    .foregroundStyle(YDColor.muted)
            }
            Spacer()
            Button("링크") {
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(YDColor.wood3)
            .frame(minWidth: 44, minHeight: 38)
        }
        .padding(10)
        .background(YDColor.cream0)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YDColor.line, lineWidth: 1)
        }
    }
}
