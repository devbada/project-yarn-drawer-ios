import SwiftUI
import UniformTypeIdentifiers

private enum PatternTool: String, CaseIterable, Identifiable {
    case view
    case highlight
    case eraser
    case check
    case note
    case currentRow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view: "보기"
        case .highlight: "형광펜"
        case .eraser: "지우개"
        case .check: "체크"
        case .note: "메모"
        case .currentRow: "현재 줄"
        }
    }

    var icon: YDIcon? {
        switch self {
        case .view: nil
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
    @State private var initialScaleFactor: Double?
    @State private var currentScaleFactor: Double?
    @State private var lastSavedPageIndex = -1
    @State private var editingNote: PatternAnnotation?
    @State private var noteText = ""
    @State private var showsNoteEditor = false
    @State private var undoStack: [[PatternAnnotation]] = []
    @State private var redoStack: [[PatternAnnotation]] = []
    @State private var selectedHighlightHex = HighlightInk.presets[0].hex
    @State private var customHighlightColor = Color(hex: 0xF9A8D4)
    @State private var currentRowAxis: CurrentRowAxis = .horizontal
    @State private var showsMissingDocumentReconnectPicker = false
    @State private var isReconnectingMissingDocument = false
    @State private var missingDocumentReconnectError: String?
    @AppStorage("viewerSelectedTool")
    private var storedSelectedTool = PatternTool.check.rawValue
    @AppStorage("viewerSelectedHighlightHex")
    private var storedSelectedHighlightHex = HighlightInk.presets[0].hex
    @AppStorage("highlightFavoriteHexes")
    private var highlightFavoriteHexes = ""
    @AppStorage("viewerCurrentRowAxis")
    private var storedCurrentRowAxis = CurrentRowAxis.horizontal.rawValue

    var body: some View {
        ZStack {
            Color(hex: 0xDED5C4).ignoresSafeArea()

            VStack(spacing: 0) {
                viewerTopBar
                if isChecksumMismatched {
                    checksumMismatchBanner
                }
                documentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if selectedTool == .highlight && !isOriginalMode {
                    highlightColorPicker
                }
                if selectedTool == .currentRow && !isOriginalMode {
                    currentRowAxisPicker
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
                        .font(YDFont.font(size: 13, weight: .bold))
                        .foregroundStyle(YDColor.cream0)
                        .padding(.horizontal, YDSpacing.x4)
                        .padding(.vertical, YDSpacing.x3)
                        .background(YDColor.ink.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.bottom, 94)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            #if DEBUG
            if isUITestDebugStateEnabled {
                debugHighlightStateView
            }
            #endif
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
                let viewerState = try await store.viewerState(for: pattern.id)
                annotations = try await store.annotations(for: pattern.id)
                initialScaleFactor = viewerState?.scaleFactor
                currentScaleFactor = viewerState?.scaleFactor
                if let restoredProgress {
                    initialPageIndex = 0
                    initialProgress = restoredProgress
                } else {
                    initialPageIndex = viewerState?.lastPageIndex ?? 0
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
                CurrentPatternSymbolsView(pattern: pattern)
                    .environmentObject(store)
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
        .sheet(isPresented: $showsMissingDocumentReconnectPicker) {
            PatternReconnectDocumentPicker(
                allowedContentTypes: [.pdf, .jpeg, .png],
                onPick: reconnectMissingDocument,
                onFailure: {
                    missingDocumentReconnectError = "파일을 다시 선택하지 못했습니다."
                }
            )
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
                    .font(YDFont.font(size: 14, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                    .lineLimit(1)
                if annotationSaveFailed {
                    Button(action: retrySaveAnnotations) {
                        Text(viewerStatus)
                            .font(YDFont.font(size: 11, weight: .bold))
                            .foregroundStyle(YDColor.danger)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("저장 다시 시도")
                } else {
                    Text(viewerStatus)
                        .font(YDFont.font(size: 11, weight: .bold))
                        .foregroundStyle(YDColor.yarn4)
                        .accessibilityLabel(viewerStatus)
                }
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
        if isFileMissing {
            missingDocumentArea
        } else if let viewURL {
            PDFKitView(
                url: viewURL,
                annotations: annotations,
                annotationTool: activePDFAnnotationTool,
                showsAnnotations: !isOriginalMode,
                allowsTextSelection: isOriginalMode,
                highlightHex: selectedHighlightHex,
                currentRowAxis: currentRowAxis,
                initialPageIndex: initialPageIndex,
                initialProgress: initialProgress,
                initialScaleFactor: initialScaleFactor,
                onAnnotationCreated: addAnnotation,
                onAnnotationDeleted: { deleteAnnotation($0) },
                onAnnotationMoved: moveAnnotation,
                onNoteRequested: beginEditingNote,
                onPageChanged: saveCurrentPage,
                onScaleChanged: saveCurrentScale
            )
                .overlay(alignment: .top) {
                    if isOriginalMode {
                        Text("원본 보기 · 표시 도구 잠김")
                            .font(YDFont.font(size: 12, weight: .bold))
                            .foregroundStyle(YDColor.ink)
                            .padding(.horizontal, YDSpacing.x3)
                            .padding(.vertical, YDSpacing.x2)
                            .background(YDColor.wood1)
                            .clipShape(Capsule())
                            .padding(.top, YDSpacing.x3)
                    } else if selectedTool == .highlight {
                        Text("한 손가락 드래그: 형광펜 · 두 손가락 드래그: 이동")
                            .font(YDFont.font(size: 12, weight: .bold))
                            .foregroundStyle(YDColor.ink)
                            .padding(.horizontal, YDSpacing.x3)
                            .padding(.vertical, YDSpacing.x2)
                            .background(YDColor.wood1.opacity(0.94))
                            .clipShape(Capsule())
                            .padding(.top, YDSpacing.x3)
                    } else if selectedTool == .view {
                        Text("보기모드 · 표시 도구 꺼짐")
                            .viewerGuideStyle()
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
                        Text("탭: 현재 줄 · 길게 누름: 선택 · 가장자리 드래그: 크기 조절")
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
            missingDocumentArea
        }
    }

    private var isFileMissing: Bool {
        !pattern.isSample && store.missingFilePatternIDs.contains(pattern.id)
    }

    private var isChecksumMismatched: Bool {
        !pattern.isSample && store.checksumMismatchPatternIDs.contains(pattern.id)
    }

    @ViewBuilder
    private var missingDocumentArea: some View {
        ZStack(alignment: .bottom) {
            MissingDocumentView(
                isReconnecting: isReconnectingMissingDocument,
                errorMessage: missingDocumentReconnectError,
                onReconnectTapped: {
                    showsMissingDocumentReconnectPicker = true
                }
            )
            #if DEBUG
            if isUITestDebugStateEnabled {
                debugReconnectFixtureButton
                    .padding(.bottom, YDSpacing.x6)
            }
            #endif
        }
    }

    private var checksumMismatchBanner: some View {
        HStack(spacing: YDSpacing.x2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(YDColor.danger)
            Text("저장된 파일이 등록 시점과 다릅니다. 상세정보에서 파일을 다시 선택해 복구하세요.")
                .font(YDFont.font(size: 12, weight: .bold))
                .foregroundStyle(YDColor.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, YDSpacing.x4)
        .padding(.vertical, YDSpacing.x2)
        .background(YDColor.danger.opacity(0.1))
    }

    private func reconnectMissingDocument(_ url: URL) {
        isReconnectingMissingDocument = true
        missingDocumentReconnectError = nil
        Task {
            defer { isReconnectingMissingDocument = false }
            do {
                try await store.reconnectPatternFile(sourceURL: url, for: pattern.id)
                if let refreshed = store.pattern(id: pattern.id) {
                    viewURL = await store.viewURL(for: refreshed)
                }
                isDocumentLoading = false
                showToast("파일을 다시 연결했습니다.")
            } catch {
                missingDocumentReconnectError = (error as? LocalizedError)?.errorDescription
                    ?? "파일을 다시 연결하지 못했습니다."
            }
        }
    }

    private var viewerToolbar: some View {
        HStack(spacing: 5) {
            ForEach(PatternTool.allCases) { tool in
                Button {
                    selectedTool = tool
                    if tool == .view {
                        showToast("보기모드로 전환했습니다.")
                    } else if tool == .highlight {
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
                            .font(YDFont.font(size: 10, weight: .bold))
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
                        .font(YDFont.font(size: 10, weight: .bold))
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
        } else if tool == .view {
            Image(systemName: "eye")
                .font(YDFont.symbol(size: 19, weight: .bold))
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "eraser")
                .font(YDFont.symbol(size: 19, weight: .bold))
                .frame(width: 22, height: 22)
        }
    }

    private var currentRowAxisPicker: some View {
        HStack(spacing: YDSpacing.x3) {
            Text("현재 줄 방향")
                .font(YDFont.font(size: 12, weight: .bold))
                .foregroundStyle(YDColor.muted)
            Picker("현재 줄 방향", selection: $currentRowAxis) {
                ForEach(CurrentRowAxis.allCases) { axis in
                    Text(axis.title).tag(axis)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190)
            Spacer()
        }
        .padding(.horizontal, YDSpacing.x4)
        .padding(.vertical, YDSpacing.x2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(YDColor.line).frame(height: 1)
        }
        .onChange(of: currentRowAxis) { _, axis in
            storedCurrentRowAxis = axis.rawValue
            showToast("\(axis.title) 현재 줄을 추가합니다.")
        }
    }

    private var highlightColorPicker: some View {
        VStack(spacing: 2) {
            HStack(spacing: YDSpacing.x2) {
                Text("형광펜 팔레트")
                    .font(YDFont.font(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.muted)
                Button {
                    undoLastHighlight()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(YDFont.symbol(size: 12, weight: .bold))
                        Text("실행 취소")
                    }
                    .font(YDFont.font(size: 12, weight: .bold))
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
                            .font(YDFont.symbol(size: 12, weight: .bold))
                        Text("즐겨찾기")
                    }
                    .font(YDFont.font(size: 12, weight: .bold))
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
                            .font(YDFont.symbol(size: 9))
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
                .font(YDFont.font(size: 13, weight: .heavy))
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
                    .font(YDFont.font(size: 14, weight: .heavy))
                    .foregroundStyle(YDColor.ink)
                Spacer()
                Text(description)
                    .font(YDFont.font(size: 12))
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
            return "편집 상태 · 저장 실패 · 탭해서 다시 시도"
        }
        return isDirty ? "편집 상태 · 변경사항 있음" : "편집 상태 · 저장됨"
    }

    private var activePDFAnnotationTool: PDFAnnotationTool? {
        guard !isOriginalMode else {
            return nil
        }
        return switch selectedTool {
        case .view: nil
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
        case .view: "보기모드로 전환했습니다."
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
        currentRowAxis = CurrentRowAxis(rawValue: storedCurrentRowAxis) ?? .horizontal
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
        // 이전 저장이 실패한 상태였다면 그 실패가 아직 저장소에 반영되지 못한 변경을
        // 메모리에 남기고 있을 수 있다. 그 상태에서 단일 append만 하면 이전 변경이
        // 파일에 영영 누락될 수 있으므로, 이번 저장은 전체 snapshot으로 처리해
        // 이전 변경까지 함께 보존한다. 실패 상태 자체도 이번 저장이 실제로
        // 성공했다고 확인되기 전까지는 지우지 않는다(아래 성공 분기에서만 해제).
        let mustUseFullSnapshot = annotationSaveFailed
        pendingAnnotationSaveCount += 1
        showToast("\(annotation.type.saveTitleWithObjectParticle) 자동 저장합니다.")

        Task {
            do {
                if annotation.type == .currentRow || mustUseFullSnapshot {
                    try await store.saveAnnotations(annotations, for: pattern.id)
                } else {
                    try await store.addAnnotation(annotation, to: pattern.id)
                }
                if annotation.type == .check {
                    try await store.updateProgress(progress(for: annotation), for: pattern.id)
                }
                annotationSaveFailed = false
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast("\(annotation.type.saveTitleWithObjectParticle) 저장했습니다.")
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast("\(annotation.type.saveTitleWithObjectParticle) 저장하지 못했습니다.")
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
        pendingAnnotationSaveCount += 1
        showToast("\(annotation.type.saveTitleWithObjectParticle) 삭제합니다.")

        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                if annotation.type == .check {
                    try await store.updateProgress(latestCheckProgress ?? 0, for: pattern.id)
                }
                annotationSaveFailed = false
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast(successMessage ?? "\(annotation.type.saveTitleWithObjectParticle) 삭제했습니다.")
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast("\(annotation.type.saveTitleWithObjectParticle) 삭제하지 못했습니다.")
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
        pendingAnnotationSaveCount += 1
        showToast("\(annotation.type.saveTitleWithObjectParticle) 이동합니다.")

        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                if annotation.type == .check {
                    try await store.updateProgress(progress(for: annotation), for: pattern.id)
                }
                annotationSaveFailed = false
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                    showToast("\(annotation.type.saveTitleWithObjectParticle) 이동했습니다.")
                }
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                isDirty = true
                showToast("\(annotation.type.saveTitleWithObjectParticle) 이동하지 못했습니다.")
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
        pendingAnnotationSaveCount += 1
        showToast(startedMessage)

        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                if updatesProgress {
                    try await store.updateProgress(latestCheckProgress ?? 0, for: pattern.id)
                }
                annotationSaveFailed = false
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
            try? await store.saveViewerState(
                pageIndex: pageIndex,
                scaleFactor: currentScaleFactor,
                for: pattern.id
            )
        }
    }

    private func saveCurrentScale(_ scaleFactor: Double) {
        currentScaleFactor = scaleFactor
        Task {
            try? await store.saveViewerState(
                pageIndex: max(0, lastSavedPageIndex),
                scaleFactor: scaleFactor,
                for: pattern.id
            )
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
                showToast("변경사항을 저장하지 못했습니다. 상단 상태를 눌러 다시 시도해 주세요.")
            }
        }
    }

    /// 저장 실패 상태에서 사용자가 직접 다시 시도할 수 있는 진입점.
    /// 성공하면 닫기/원본 보기 전환처럼 보류 중이던 동작(`protectedAction`)이 있을 때
    /// 그 동작까지 이어서 완료해, 실패 때문에 조용히 무시된 요청이 남지 않게 한다.
    private func retrySaveAnnotations() {
        guard annotationSaveFailed else {
            return
        }
        pendingAnnotationSaveCount += 1
        showToast("저장을 다시 시도합니다.")
        Task {
            do {
                try await store.saveAnnotations(annotations, for: pattern.id)
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = false
                if pendingAnnotationSaveCount == 0 {
                    isDirty = false
                }
                showToast("저장을 다시 시도해 성공했습니다.")
                performProtectedAction()
            } catch {
                pendingAnnotationSaveCount = max(0, pendingAnnotationSaveCount - 1)
                annotationSaveFailed = true
                showToast("다시 시도했지만 저장하지 못했습니다.")
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

    #if DEBUG
    /// UI 테스트가 실제 화면 렌더링과 무관하게 저장된 highlight 상태(개수, 마지막 색상)를
    /// 결정론적으로 검증할 수 있도록 노출하는 디버그 전용 훅. `YARN_DRAWER_UI_TEST_MODE`
    /// 환경변수가 설정된 경우에만(테스트 실행 시에만) 나타나며, 일반 빌드/릴리즈 UX에는
    /// 절대 노출되지 않는다.
    private var isUITestDebugStateEnabled: Bool {
        ProcessInfo.processInfo.environment["YARN_DRAWER_UI_TEST_MODE"] == "1"
    }

    private var debugHighlightStateText: String {
        let highlights = annotations.filter { $0.type == .highlight }
        let lastHex = highlights
            .max { $0.createdAt < $1.createdAt }?
            .resolvedHighlightHex ?? "none"
        // totalCount는 형광펜이 아닌 체크/메모/현재 줄 등도 포함한 전체 annotation
        // 개수로, 저장 실패 이후 재시도 없이 이어간 편집이 실제로 유지되는지
        // (형광펜이 아닌 도구를 쓴 경우까지) 검증할 수 있도록 별도로 노출한다.
        return "totalCount=\(annotations.count);highlightCount=\(highlights.count);lastHighlightHex=\(lastHex)"
    }

    private var debugHighlightStateView: some View {
        Text(debugHighlightStateText)
            .font(.system(size: 1))
            .opacity(0.01)
            .accessibilityIdentifier("debugHighlightState")
            .allowsHitTesting(false)
    }

    /// 파일 누락 화면에서 시스템 문서 picker를 거치지 않고 바로 재연결을 검증하기 위한
    /// 디버그 전용 버튼. `YARN_DRAWER_UI_TEST_MODE`일 때만 나타나며 일반 빌드에는 없다.
    private var debugReconnectFixtureButton: some View {
        Button("테스트용 파일로 재연결") {
            guard let fixtureURL = UITestPDFFixture.makeSamplePDF() else {
                return
            }
            reconnectMissingDocument(fixtureURL)
        }
        .font(YDFont.font(size: 12, weight: .bold))
        .foregroundStyle(YDColor.cream0)
        .padding(.horizontal, YDSpacing.x3)
        .frame(minHeight: 36)
        .background(YDColor.wood3)
        .clipShape(Capsule())
        .accessibilityIdentifier("debugReconnectWithFixture")
    }
    #endif
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

    /// 받침 유무에 따라 "을/를"을 올바르게 붙인 목적어 형태.
    var saveTitleWithObjectParticle: String {
        guard
            let last = saveTitle.unicodeScalars.last,
            (0xAC00...0xD7A3).contains(last.value)
        else {
            return "\(saveTitle)을"
        }
        let hasBatchim = (last.value - 0xAC00) % 28 != 0
        return "\(saveTitle)\(hasBatchim ? "을" : "를")"
    }
}

private extension View {
    func viewerGuideStyle() -> some View {
        font(YDFont.font(size: 12, weight: .bold))
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
                .font(YDFont.font(size: 14, weight: .bold))
                .foregroundStyle(YDColor.ink)
            Text("저장된 페이지와 표시를 복원하고 있습니다.")
                .font(YDFont.font(size: 12))
                .foregroundStyle(YDColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xDED5C4))
    }
}

private struct MissingDocumentView: View {
    let isReconnecting: Bool
    let errorMessage: String?
    let onReconnectTapped: () -> Void

    var body: some View {
        VStack(spacing: YDSpacing.x3) {
            YDIconView(icon: .storage, size: 34)
                .foregroundStyle(YDColor.wood3)
            Text("작업용 파일을 열 수 없습니다.")
                .font(YDFont.font(size: 15, weight: .bold))
                .foregroundStyle(YDColor.ink)
            Text("원본 파일이 없어졌거나 이동됐습니다. 파일을 다시 선택하면 복구할 수 있습니다.")
                .font(YDFont.font(size: 12))
                .foregroundStyle(YDColor.muted)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(YDFont.font(size: 12, weight: .bold))
                    .foregroundStyle(YDColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.top, YDSpacing.x1)
            }

            Button(action: onReconnectTapped) {
                Text(isReconnecting ? "다시 연결하는 중..." : "파일 다시 선택")
                    .font(YDFont.font(size: 14, weight: .heavy))
                    .foregroundStyle(YDColor.cream0)
                    .frame(minWidth: 180, minHeight: YDLayout.minimumTouchTarget)
                    .background(YDColor.ink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isReconnecting)
            .accessibilityLabel("파일 다시 선택")
            .padding(.top, YDSpacing.x2)
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
                    .font(YDFont.font(size: 24, weight: .bold))
                    .foregroundStyle(YDColor.ink)

                VStack(alignment: .leading, spacing: YDSpacing.x4) {
                    ForEach(lines.indices, id: \.self) { index in
                        Button {
                            applyTool(at: index)
                        } label: {
                            HStack(alignment: .top, spacing: 4) {
                                if lines[index].checked && !isOriginalMode {
                                    Text("✓")
                                        .font(YDFont.font(size: 15, weight: .black))
                                        .foregroundStyle(YDColor.yarn4)
                                }
                                Text(lines[index].text)
                                    .foregroundStyle(Color(hex: 0x4F473B))
                                    .multilineTextAlignment(.leading)
                            }
                            .font(YDFont.font(size: 15))
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
        case .view:
            return
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
    @EnvironmentObject private var store: PatternStore
    @Environment(\.openURL) private var openURL

    let pattern: PatternItem
    @State private var query = ""
    @State private var editorContext: SymbolEditorContext?
    @State private var deleteCandidate: KnitSymbol?
    @State private var pendingLinkSymbol: KnitSymbol?
    @State private var detailSymbol: KnitSymbol?
    @State private var toastMessage: String?

    private var filteredSymbols: [KnitSymbol] {
        store.symbols(for: pattern.id, matching: query)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: YDSpacing.x3) {
                        Text("\(pattern.title) 전용 기호와 공통 기호를 함께 표시합니다.")
                            .font(YDFont.font(size: 13))
                            .foregroundStyle(YDColor.yarn4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(YDColor.surfaceGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack(spacing: YDSpacing.x3) {
                            YDIconView(icon: .search, size: 20)
                                .foregroundStyle(YDColor.muted)
                            TextField("기호명, 약어 검색", text: $query)
                                .font(YDFont.font(size: 14))
                        }
                        .padding(.horizontal, 15)
                        .frame(minHeight: 50)
                        .background(YDColor.cream0)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(YDColor.line, lineWidth: 1)
                        }

                        if filteredSymbols.isEmpty {
                            Text("표시할 기호가 없습니다.")
                                .font(YDFont.font(size: 14, weight: .bold))
                                .foregroundStyle(YDColor.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, YDSpacing.x8)
                                .background(YDColor.cream0.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            ForEach(filteredSymbols) { symbol in
                                symbolRow(symbol)
                            }
                        }
                    }
                    .padding(YDSpacing.x4)
                }
                .background(YDColor.cream0)

                if let toastMessage {
                    Text(toastMessage)
                        .font(YDFont.font(size: 13, weight: .bold))
                        .foregroundStyle(YDColor.cream0)
                        .padding(.horizontal, YDSpacing.x4)
                        .padding(.vertical, YDSpacing.x3)
                        .background(YDColor.ink.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.bottom, YDSpacing.x4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("현재 도안 기호")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("등록") {
                        editorContext = SymbolEditorContext(
                            scope: .pattern,
                            patternID: pattern.id,
                            symbol: nil
                        )
                    }
                    .font(YDFont.font(size: 17, weight: .bold))
                    .foregroundStyle(YDColor.yarn4)
                }
            }
        }
        .confirmationDialog(
            "외부 링크 열기",
            isPresented: Binding(
                get: { pendingLinkSymbol != nil },
                set: { if !$0 { pendingLinkSymbol = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingLinkSymbol {
                Button("\(pendingLinkSymbol.linkDomain) 열기") {
                    guard let linkURL = pendingLinkSymbol.linkURL else {
                        return
                    }
                    openURL(linkURL)
                    showToast("\(pendingLinkSymbol.linkDomain)을 열었습니다.")
                    self.pendingLinkSymbol = nil
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            if let pendingLinkSymbol {
                Text("\(pendingLinkSymbol.name) 설명을 시스템 브라우저에서 엽니다.")
            }
        }
        .confirmationDialog(
            "기호를 삭제할까요?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let deleteCandidate {
                Button("삭제", role: .destructive) {
                    deleteSymbol(deleteCandidate)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            if let deleteCandidate {
                Text("\(deleteCandidate.name)을 삭제합니다.")
            }
        }
        .sheet(item: $editorContext) { context in
            SymbolEditorView(context: context) {
                showToast(context.symbol == nil ? "기호를 등록했습니다." : "기호를 수정했습니다.")
            }
            .environmentObject(store)
        }
        .sheet(item: $detailSymbol) { symbol in
            SymbolDetailView(
                symbol: symbol,
                canModify: !symbol.isSystem,
                onOpenLink: {
                    pendingLinkSymbol = symbol
                },
                onEdit: {
                    detailSymbol = nil
                    editorContext = SymbolEditorContext(
                        scope: symbol.scope,
                        patternID: symbol.patternID ?? pattern.id,
                        symbol: symbol
                    )
                },
                onDelete: {
                    detailSymbol = nil
                    deleteCandidate = symbol
                }
            )
        }
    }

    private func symbolRow(_ symbol: KnitSymbol) -> some View {
        HStack(spacing: 11) {
            KnitSymbolMark(symbol: symbol, size: 48, cornerRadius: 13)
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.name)
                    .font(YDFont.font(size: 14, weight: .bold))
                    .foregroundStyle(YDColor.ink)
                Text(symbol.metadata)
                    .font(YDFont.font(size: 12))
                    .foregroundStyle(YDColor.muted)
            }
            Spacer()
            if symbol.linkURL != nil {
                Button("링크") {
                    pendingLinkSymbol = symbol
                }
                .font(YDFont.font(size: 12, weight: .heavy))
                .foregroundStyle(YDColor.wood3)
                .frame(minWidth: 44, minHeight: 38)
            }
            if !symbol.isSystem {
                Menu {
                    Button("수정") {
                        editorContext = SymbolEditorContext(
                            scope: symbol.scope,
                            patternID: symbol.patternID ?? pattern.id,
                            symbol: symbol
                        )
                    }
                    Button("삭제", role: .destructive) {
                        deleteCandidate = symbol
                    }
                } label: {
                    YDIconView(icon: .more, size: 21)
                        .foregroundStyle(YDColor.muted)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(10)
        .background(YDColor.cream0)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YDColor.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            detailSymbol = symbol
        }
    }

    private func deleteSymbol(_ symbol: KnitSymbol) {
        Task {
            do {
                try await store.deleteSymbol(symbol.id)
                deleteCandidate = nil
                showToast("기호를 삭제했습니다.")
            } catch {
                deleteCandidate = nil
                showToast(error.localizedDescription)
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
