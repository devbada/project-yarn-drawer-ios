import SwiftUI

struct SymbolsView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var query = ""
    @State private var toastMessage: String?
    @State private var pendingLinkSymbol: KnitSymbol?
    @State private var editorContext: SymbolEditorContext?
    @State private var deleteCandidate: KnitSymbol?
    @State private var detailSymbol: KnitSymbol?

    private var filteredSymbols: [KnitSymbol] {
        store.commonSymbols(matching: query)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("기호")
                                .font(YDFont.font(size: 32, weight: .bold))
                                .tracking(-1.1)
                                .foregroundStyle(YDColor.ink)
                            Text("공통 기호를 관리합니다. 도안 전용 기호는 뷰어에서 등록합니다.")
                                .font(YDFont.font(size: 14))
                                .foregroundStyle(YDColor.muted)
                        }
                        Spacer()
                        YDIconButton(
                            icon: .plus,
                            accessibilityLabel: "새 기호 등록"
                        ) {
                            editorContext = SymbolEditorContext(
                                scope: .common,
                                patternID: nil,
                                symbol: nil
                            )
                        }
                    }

                    HStack(spacing: YDSpacing.x3) {
                        YDIconView(icon: .search, size: 20)
                            .foregroundStyle(YDColor.muted)
                        TextField("기호명, 약어 검색", text: $query)
                    }
                    .padding(.horizontal, 15)
                    .frame(minHeight: 50)
                    .background(YDColor.cream0)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(YDColor.line, lineWidth: 1)
                    }

                    LazyVGrid(
                        columns: horizontalSizeClass == .regular
                            ? [GridItem(.adaptive(minimum: 300), spacing: 10)]
                            : [GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(filteredSymbols) { symbol in
                            symbolCard(symbol)
                        }
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 36 : YDSpacing.x4)
                .padding(.vertical, horizontalSizeClass == .regular ? 28 : 22)
            }

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
        .confirmationDialog(
            "외부 링크 열기",
            isPresented: Binding(
                get: { pendingLinkSymbol != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingLinkSymbol = nil
                    }
                }
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
                        patternID: symbol.patternID,
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

    private func symbolCard(_ symbol: KnitSymbol) -> some View {
        HStack(spacing: YDSpacing.x3) {
            KnitSymbolMark(symbol: symbol, size: 58, cornerRadius: 16)

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
                .padding(.horizontal, 8)
                .background(YDColor.cream0)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(YDColor.line, lineWidth: 1)
                }
            }
            if !symbol.isSystem {
                Menu {
                    Button("수정") {
                        editorContext = SymbolEditorContext(
                            scope: symbol.scope,
                            patternID: symbol.patternID,
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
        .padding(11)
        .ydSurfaceCard()
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

struct SymbolEditorContext: Identifiable {
    let id = UUID()
    let scope: KnitSymbolScope
    let patternID: PatternItem.ID?
    let symbol: KnitSymbol?
}

struct SymbolEditorView: View {
    @EnvironmentObject private var store: PatternStore
    @Environment(\.dismiss) private var dismiss

    let context: SymbolEditorContext
    var onSaved: () -> Void

    @State private var scope: KnitSymbolScope
    @State private var drawingStrokes: [[NormalizedPoint]]
    @State private var name: String
    @State private var abbreviation: String
    @State private var description: String
    @State private var linkURLString: String
    @State private var isFavorite: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var invalidFields = Set<SymbolValidationField>()

    init(
        context: SymbolEditorContext,
        onSaved: @escaping () -> Void
    ) {
        self.context = context
        self.onSaved = onSaved
        _scope = State(initialValue: context.symbol?.scope ?? context.scope)
        _drawingStrokes = State(initialValue: context.symbol?.drawingStrokes ?? [])
        _name = State(initialValue: context.symbol?.name ?? "")
        _abbreviation = State(initialValue: context.symbol?.abbreviation ?? "")
        _description = State(initialValue: context.symbol?.description ?? "")
        _linkURLString = State(initialValue: context.symbol?.linkURLString ?? "")
        _isFavorite = State(initialValue: context.symbol?.isFavorite ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    if context.patternID != nil {
                        Picker("범위", selection: $scope) {
                            ForEach(KnitSymbolScope.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: YDSpacing.x2) {
                        HStack {
                            Text("기호 그리기")
                                .font(YDFont.font(size: 12, weight: .heavy))
                                .foregroundStyle(isDrawingInvalid ? YDColor.danger : YDColor.muted)
                            if isDrawingInvalid {
                                Text("기호를 그려 주세요.")
                                    .font(YDFont.font(size: 12, weight: .bold))
                                    .foregroundStyle(YDColor.danger)
                            }
                            Spacer()
                            Button("지우기") {
                                drawingStrokes.removeAll()
                            }
                            .font(YDFont.font(size: 12, weight: .bold))
                            .foregroundStyle(YDColor.yarn4)
                            .disabled(drawingStrokes.isEmpty)
                        }
                        SymbolCanvasView(strokes: $drawingStrokes)
                            .frame(height: 210)
                            .overlay {
                                if isDrawingInvalid {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(YDColor.danger, lineWidth: 2)
                                }
                            }
                    }

                    if !drawingStrokes.isEmpty {
                        HStack(spacing: YDSpacing.x3) {
                            SymbolDrawingView(strokes: drawingStrokes)
                                .foregroundStyle(YDColor.yarn4)
                                .frame(width: 62, height: 62)
                                .background(YDColor.surfaceGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("그린 기호가 카드와 뷰어에 표시됩니다.")
                                .font(YDFont.font(size: 13))
                                .foregroundStyle(YDColor.muted)
                            Spacer()
                        }
                        .padding(12)
                        .background(YDColor.cream0)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(YDColor.line, lineWidth: 1)
                        }
                    }
                    field(
                        "이름",
                        isInvalid: invalidFields.contains(.name) && !isNameValid,
                        message: "기호 이름을 입력해 주세요."
                    ) {
                        TextField("예: 바늘비우기", text: $name)
                    }
                    field("약어") {
                        TextField("예: yo, m1l", text: $abbreviation)
                            .textInputAutocapitalization(.never)
                    }
                    field("설명") {
                        TextField("짧은 설명", text: $description, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    field(
                        "링크",
                        isInvalid: invalidFields.contains(.linkURL) && !isLinkURLValid,
                        message: "https 주소로 입력해 주세요."
                    ) {
                        TextField("https://", text: $linkURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    Toggle("즐겨찾기", isOn: $isFavorite)
                        .font(YDFont.font(size: 14, weight: .bold))
                        .foregroundStyle(YDColor.ink)
                        .padding(14)
                        .background(YDColor.cream0)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(YDColor.line, lineWidth: 1)
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(YDFont.font(size: 13))
                            .foregroundStyle(YDColor.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(YDColor.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(YDSpacing.x4)
            }
            .background(YDColor.cream1)
            .navigationTitle(context.symbol == nil ? "기호 등록" : "기호 수정")
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
                    .disabled(isSaving)
                }
            }
        }
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
                .font(YDFont.font(size: 14))
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

    private func save() {
        invalidFields = validationFields()
        guard invalidFields.isEmpty else {
            errorMessage = "필수 정보를 입력해 주세요."
            return
        }
        isSaving = true
        errorMessage = nil
        let draft = KnitSymbolDraft(
            id: context.symbol?.id,
            scope: scope,
            patternID: scope == .pattern ? context.patternID : nil,
            glyph: "그림",
            drawingStrokes: drawingStrokes,
            name: name,
            abbreviation: abbreviation,
            description: description,
            linkURLString: linkURLString,
            isFavorite: isFavorite
        )
        Task {
            defer { isSaving = false }
            do {
                try await store.saveSymbol(draft)
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func validationFields() -> Set<SymbolValidationField> {
        var fields = Set<SymbolValidationField>()
        if drawingStrokes.isEmpty {
            fields.insert(.drawing)
        }
        if !isNameValid {
            fields.insert(.name)
        }
        if !isLinkURLValid {
            fields.insert(.linkURL)
        }
        return fields
    }

    private var isDrawingInvalid: Bool {
        invalidFields.contains(.drawing) && drawingStrokes.isEmpty
    }

    private var isNameValid: Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedName.isEmpty && normalizedName.count <= 60
    }

    private var isLinkURLValid: Bool {
        let normalizedLinkURLString = linkURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLinkURLString.isEmpty else {
            return true
        }
        guard let url = URL(string: normalizedLinkURLString), url.scheme == "https" else {
            return false
        }
        return url.host() != nil || url.host != nil
    }
}

private enum SymbolValidationField {
    case drawing
    case name
    case linkURL
}

struct SymbolDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let symbol: KnitSymbol
    let canModify: Bool
    var onOpenLink: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: YDSpacing.x4) {
                    KnitSymbolMark(symbol: symbol, size: 132, cornerRadius: 28)
                        .padding(.top, YDSpacing.x2)

                    VStack(spacing: 6) {
                        Text(symbol.name)
                            .font(YDFont.font(size: 24, weight: .heavy))
                            .foregroundStyle(YDColor.ink)
                            .multilineTextAlignment(.center)
                        Text(symbol.scope.title)
                            .font(YDFont.font(size: 13, weight: .bold))
                            .foregroundStyle(YDColor.yarn4)
                    }

                    VStack(spacing: 0) {
                        detailRow("약어", nonEmpty(symbol.abbreviation))
                        detailRow("설명", nonEmpty(symbol.description))
                        detailRow("링크", symbol.linkDomain)
                        detailRow("즐겨찾기", symbol.isFavorite ? "예" : "아니오")
                    }
                    .background(YDColor.cream0)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(YDColor.line, lineWidth: 1)
                    }

                    VStack(spacing: YDSpacing.x2) {
                        if symbol.linkURL != nil {
                            Button("링크 열기") {
                                dismiss()
                                onOpenLink()
                            }
                            .buttonStyle(YDSecondaryButtonStyle())
                        }

                        if canModify {
                            Button("수정") {
                                dismiss()
                                onEdit()
                            }
                            .buttonStyle(YDPrimaryButtonStyle())

                            Button("삭제", role: .destructive) {
                                dismiss()
                                onDelete()
                            }
                            .font(YDFont.font(size: 14, weight: .heavy))
                            .foregroundStyle(YDColor.danger)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                            .background(YDColor.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(YDSpacing.x4)
            }
            .background(YDColor.cream1)
            .navigationTitle("기호 상세")
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

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: YDSpacing.x3) {
            Text(title)
                .font(YDFont.font(size: 12, weight: .heavy))
                .foregroundStyle(YDColor.muted)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(YDFont.font(size: 14))
                .foregroundStyle(YDColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, YDSpacing.x4)
        .padding(.vertical, YDSpacing.x3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(YDColor.line)
                .frame(height: 1)
        }
    }

    private func nonEmpty(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? "-" : trimmedValue
    }
}

struct KnitSymbolMark: View {
    let symbol: KnitSymbol
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let strokes = symbol.drawingStrokes, !strokes.isEmpty {
                SymbolDrawingView(strokes: strokes)
                    .foregroundStyle(YDColor.yarn4)
                    .padding(size * 0.16)
            } else {
                Text(symbol.glyph)
                    .font(YDFont.font(size: size * 0.40, weight: .black))
                    .foregroundStyle(YDColor.yarn4)
            }
        }
        .frame(width: size, height: size)
        .background(YDColor.surfaceGreen)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SymbolDrawingView: View {
    let strokes: [[NormalizedPoint]]

    var body: some View {
        Canvas { context, size in
            for stroke in strokes where stroke.count > 1 {
                var path = Path()
                for (index, point) in stroke.enumerated() {
                    let cgPoint = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    if index == 0 {
                        path.move(to: cgPoint)
                    } else {
                        path.addLine(to: cgPoint)
                    }
                }
                context.stroke(
                    path,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: max(2, size.width * 0.055), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

private struct SymbolCanvasView: View {
    @Binding var strokes: [[NormalizedPoint]]
    @State private var currentStroke: [NormalizedPoint] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                YDColor.cream0
                SymbolDrawingView(strokes: strokes + (currentStroke.isEmpty ? [] : [currentStroke]))
                    .foregroundStyle(YDColor.ink)
                    .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(YDColor.line, lineWidth: 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let point = normalizedPoint(value.location, in: proxy.size) else {
                            return
                        }
                        currentStroke.append(point)
                    }
                    .onEnded { _ in
                        if currentStroke.count > 1 {
                            strokes.append(currentStroke)
                        }
                        currentStroke = []
                    }
            )
        }
    }

    private func normalizedPoint(_ point: CGPoint, in size: CGSize) -> NormalizedPoint? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let clippedPoint = CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
        return NormalizedPoint(
            x: Double(clippedPoint.x / size.width),
            y: Double(clippedPoint.y / size.height)
        )
    }
}
