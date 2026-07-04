import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let annotations: [PatternAnnotation]
    let annotationTool: PDFAnnotationTool?
    let showsAnnotations: Bool
    let allowsTextSelection: Bool
    let highlightHex: String
    let currentRowAxis: CurrentRowAxis
    let initialPageIndex: Int
    let initialProgress: Double?
    let initialScaleFactor: Double?
    let onAnnotationCreated: (PatternAnnotation) -> Void
    let onAnnotationDeleted: (PatternAnnotation) -> Void
    let onAnnotationMoved: (PatternAnnotation) -> Void
    let onNoteRequested: (PatternAnnotation) -> Void
    let onPageChanged: (Int) -> Void
    let onScaleChanged: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(YDColor.cream3)
        view.pageOverlayViewProvider = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.configureTextSelection(
            allowsTextSelection,
            in: view
        )

        let highlightGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHighlightGesture(_:))
        )
        highlightGesture.minimumNumberOfTouches = 1
        highlightGesture.maximumNumberOfTouches = 1
        highlightGesture.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        highlightGesture.cancelsTouchesInView = true
        view.addGestureRecognizer(highlightGesture)

        let placementGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePlacementGesture(_:))
        )
        placementGesture.cancelsTouchesInView = true
        view.addGestureRecognizer(placementGesture)

        let selectionGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSelectionGesture(_:))
        )
        selectionGesture.minimumPressDuration = 0.35
        selectionGesture.cancelsTouchesInView = true
        selectionGesture.delegate = context.coordinator
        view.addGestureRecognizer(selectionGesture)

        let moveGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMoveGesture(_:))
        )
        moveGesture.minimumNumberOfTouches = 1
        moveGesture.maximumNumberOfTouches = 1
        moveGesture.cancelsTouchesInView = true
        moveGesture.delegate = context.coordinator
        view.addGestureRecognizer(moveGesture)

        context.coordinator.pdfView = view
        context.coordinator.highlightGesture = highlightGesture
        context.coordinator.placementGesture = placementGesture
        context.coordinator.selectionGesture = selectionGesture
        context.coordinator.moveGesture = moveGesture
        context.coordinator.startObservingPageChanges()
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncAnnotations(
            annotations,
            showsAnnotations: showsAnnotations
        )

        if view.document?.documentURL != url {
            context.coordinator.loadDocument(
                from: url,
                initialPageIndex: initialPageIndex,
                initialProgress: initialProgress,
                initialScaleFactor: initialScaleFactor
            )
        }

        context.coordinator.highlightGesture?.isEnabled = annotationTool == .highlight
        context.coordinator.placementGesture?.isEnabled =
            annotationTool == .check ||
            annotationTool == .note ||
            annotationTool == .currentRow ||
            annotationTool == .eraser
        context.coordinator.selectionGesture?.isEnabled =
            annotationTool == .check ||
            annotationTool == .note ||
            annotationTool == .currentRow
        context.coordinator.moveGesture?.isEnabled =
            annotationTool == .check ||
            annotationTool == .note ||
            annotationTool == .currentRow
        context.coordinator.clearSelectionIfSelectionIsDisabled(
            annotationTool == .check ||
            annotationTool == .note ||
            annotationTool == .currentRow
        )
        context.coordinator.configureScrolling(for: annotationTool == .highlight)
        context.coordinator.configureTextSelection(
            allowsTextSelection,
            in: view
        )
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PDFViewDelegate, UIGestureRecognizerDelegate {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        weak var highlightGesture: UIPanGestureRecognizer?
        weak var placementGesture: UITapGestureRecognizer?
        weak var selectionGesture: UILongPressGestureRecognizer?
        weak var moveGesture: UIPanGestureRecognizer?

        private var activePage: PDFPage?
        private var draftViewPoints: [CGPoint] = []
        private weak var draftView: HighlightStrokeDraftView?
        private var draftID: UUID?
        private var movingAnnotation: PatternAnnotation?
        private weak var movingPage: PDFPage?
        private var movingTouchOffset = CGPoint.zero
        private var currentRowDragMode: CurrentRowDragMode = .move
        private var selectedAnnotationID: PatternAnnotation.ID?
        private var currentAnnotations: [PatternAnnotation]
        private var showsAnnotations: Bool
        private var visibleOverlays: [Int: HighlightPageOverlayView] = [:]
        private weak var currentRowControlView: CurrentRowControlView?
        private var isRestoringPage = false
        private var lastSavedScaleFactor: Double?

        init(parent: PDFKitView) {
            self.parent = parent
            currentAnnotations = parent.annotations
            showsAnnotations = parent.showsAnnotations
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func startObservingPageChanges() {
            guard let pdfView else {
                return
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePageChanged),
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScaleChanged),
                name: Notification.Name.PDFViewScaleChanged,
                object: pdfView
            )
        }

        func loadDocument(
            from url: URL,
            initialPageIndex: Int,
            initialProgress: Double?,
            initialScaleFactor: Double?
        ) {
            guard
                let pdfView,
                let document = PDFDocument(url: url),
                document.pageCount > 0
            else {
                return
            }
            isRestoringPage = true
            pdfView.document = document
            let restoreTarget = restoreTarget(
                pageCount: document.pageCount,
                initialPageIndex: initialPageIndex,
                initialProgress: initialProgress
            )
            let safeIndex = restoreTarget.pageIndex
            guard let page = document.page(at: safeIndex) else {
                isRestoringPage = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, let pdfView = self.pdfView else {
                    return
                }
                pdfView.layoutIfNeeded()
                self.applyRestore(
                    page: page,
                    pageProgress: restoreTarget.pageProgress,
                    scaleFactor: initialScaleFactor,
                    attempt: 0
                )
            }
        }

        private func applyRestore(
            page: PDFPage,
            pageProgress: CGFloat?,
            scaleFactor: Double?,
            attempt: Int
        ) {
            guard let pdfView else {
                isRestoringPage = false
                return
            }

            pdfView.layoutIfNeeded()
            if let pageProgress {
                let bounds = page.bounds(for: .cropBox)
                let targetHeight = min(max(bounds.height * 0.04, 8), bounds.height)
                let y = bounds.maxY - (bounds.height * pageProgress)
                let clampedY = min(
                    max(bounds.minY, y - (targetHeight / 2)),
                    bounds.maxY - targetHeight
                )
                let targetRect = CGRect(
                    x: bounds.minX,
                    y: clampedY,
                    width: bounds.width,
                    height: targetHeight
                )
                pdfView.go(to: page)
                pdfView.go(to: targetRect, on: page)
            } else {
                pdfView.go(to: page)
            }
            if let scaleFactor {
                let scale = min(
                    max(CGFloat(scaleFactor), pdfView.minScaleFactor),
                    pdfView.maxScaleFactor
                )
                pdfView.scaleFactor = scale
                lastSavedScaleFactor = Double(scale)
            }

            guard attempt < 2 else {
                isRestoringPage = false
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.applyRestore(
                    page: page,
                    pageProgress: pageProgress,
                    scaleFactor: scaleFactor,
                    attempt: attempt + 1
                )
            }
        }

        private func restoreTarget(
            pageCount: Int,
            initialPageIndex: Int,
            initialProgress: Double?
        ) -> (pageIndex: Int, pageProgress: CGFloat?) {
            guard
                let initialProgress,
                pageCount > 0
            else {
                return (
                    min(max(0, initialPageIndex), pageCount - 1),
                    nil
                )
            }

            let progress = min(max(initialProgress, 0), 1)
            let rawPosition = progress * Double(pageCount)
            let pageIndex = min(max(0, Int(rawPosition)), pageCount - 1)
            let pageProgress = progress >= 1
                ? CGFloat(1)
                : CGFloat(rawPosition - floor(rawPosition))
            return (pageIndex, pageProgress)
        }

        func configureScrolling(for isHighlighting: Bool) {
            guard let scrollView = pdfView?.firstDescendant(of: UIScrollView.self) else {
                return
            }
            scrollView.panGestureRecognizer.minimumNumberOfTouches = isHighlighting ? 2 : 1
        }

        func configureTextSelection(
            _ allowsTextSelection: Bool,
            in pdfView: PDFView
        ) {
            pdfView.isInMarkupMode = !allowsTextSelection
            if !allowsTextSelection, pdfView.currentSelection != nil {
                pdfView.clearSelection()
            }
        }

        func syncAnnotations(
            _ annotations: [PatternAnnotation],
            showsAnnotations: Bool
        ) {
            currentAnnotations = annotations
            self.showsAnnotations = showsAnnotations
            if let selectedAnnotationID,
               !annotations.contains(where: { $0.id == selectedAnnotationID })
            {
                self.selectedAnnotationID = nil
                removeCurrentRowControls()
            }

            for (pageIndex, overlay) in visibleOverlays {
                overlay.annotations = showsAnnotations
                    ? annotations.filter { $0.pageIndex == pageIndex }
                    : []
                overlay.selectedAnnotationID = self.selectedAnnotationID
            }
            updateCurrentRowControls()
        }

        func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            guard
                let document = view.document,
                document.index(for: page) >= 0
            else {
                return nil
            }

            let pageIndex = document.index(for: page)
            let overlay = HighlightPageOverlayView()
            overlay.isUserInteractionEnabled = false
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.contentMode = .redraw
            overlay.annotations = showsAnnotations
                ? currentAnnotations.filter { $0.pageIndex == pageIndex }
                : []
            overlay.selectedAnnotationID = selectedAnnotationID
            visibleOverlays[pageIndex] = overlay
            return overlay
        }

        func pdfView(
            _ pdfView: PDFView,
            willEndDisplayingOverlayView overlayView: UIView,
            for page: PDFPage
        ) {
            guard
                let pageIndex = pdfView.document?.index(for: page),
                visibleOverlays[pageIndex] === overlayView
            else {
                return
            }
            visibleOverlays.removeValue(forKey: pageIndex)
        }

        @objc private func handlePageChanged() {
            guard
                !isRestoringPage,
                let pdfView,
                let document = pdfView.document,
                let currentPage = pdfView.currentPage
            else {
                return
            }
            let pageIndex = document.index(for: currentPage)
            guard pageIndex >= 0 else {
                return
            }
            updateCurrentRowControls()
            parent.onPageChanged(pageIndex)
        }

        @objc private func handleScaleChanged() {
            guard
                !isRestoringPage,
                let pdfView
            else {
                return
            }
            let scale = Double(pdfView.scaleFactor)
            guard abs((lastSavedScaleFactor ?? -1) - scale) > 0.01 else {
                return
            }
            lastSavedScaleFactor = scale
            updateCurrentRowControls()
            parent.onScaleChanged(scale)
        }

        func clearSelectionIfSelectionIsDisabled(_ isSelectionEnabled: Bool) {
            if !isSelectionEnabled {
                clearSelectedAnnotation()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === moveGesture else {
                return true
            }
            guard
                let selectedAnnotationID,
                let pdfView,
                let document = pdfView.document,
                let tool = parent.annotationTool,
                tool == .check || tool == .note || tool == .currentRow
            else {
                removeCurrentRowControls()
                return false
            }
            let location = gestureRecognizer.location(in: pdfView)
            guard
                let page = pdfView.page(for: location, nearest: true),
                document.index(for: page) >= 0
            else {
                return false
            }
            let pagePoint = pdfView.convert(location, to: page)
            return selectedMovableAnnotation(
                id: selectedAnnotationID,
                at: pagePoint,
                on: page,
                in: document
            ) != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            (gestureRecognizer === selectionGesture && otherGestureRecognizer === moveGesture) ||
            (gestureRecognizer === moveGesture && otherGestureRecognizer === selectionGesture)
        }

        @objc func handleSelectionGesture(_ gesture: UILongPressGestureRecognizer) {
            guard
                gesture.state == .began,
                let pdfView,
                let document = pdfView.document,
                let tool = parent.annotationTool,
                tool == .check || tool == .note || tool == .currentRow
            else {
                return
            }

            let location = gesture.location(in: pdfView)
            guard
                let page = pdfView.page(for: location, nearest: true),
                document.index(for: page) >= 0
            else {
                return
            }
            let pagePoint = pdfView.convert(location, to: page)
            guard
                let annotation = existingMovableAnnotation(
                    at: pagePoint,
                    on: page,
                    in: document
                )
            else {
                clearSelectedAnnotation()
                return
            }
            selectedAnnotationID = annotation.id
            updateOverlay(for: annotation.pageIndex)
            updateCurrentRowControls()
        }

        @objc func handleMoveGesture(_ gesture: UIPanGestureRecognizer) {
            guard
                let selectedAnnotationID,
                let pdfView,
                let document = pdfView.document,
                let tool = parent.annotationTool,
                tool == .check || tool == .note || tool == .currentRow
            else {
                clearMoveState()
                return
            }

            let location = gesture.location(in: pdfView)
            guard
                let page = pdfView.page(for: location, nearest: true),
                document.index(for: page) >= 0
            else {
                if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                    clearMoveState()
                }
                return
            }
            let pagePoint = pdfView.convert(location, to: page)

            switch gesture.state {
            case .began:
                beginMovingAnnotation(
                    id: selectedAnnotationID,
                    at: pagePoint,
                    on: page,
                    in: document
                )
            case .changed:
                updateMovingAnnotation(
                    at: pagePoint,
                    on: page,
                    in: document,
                    shouldSave: false
                )
            case .ended:
                updateMovingAnnotation(
                    at: pagePoint,
                    on: page,
                    in: document,
                    shouldSave: true
                )
            case .cancelled, .failed:
                clearMoveState()
                syncAnnotations(
                    parent.annotations,
                    showsAnnotations: parent.showsAnnotations
                )
            default:
                break
            }
        }

        @objc func handlePlacementGesture(_ gesture: UITapGestureRecognizer) {
            guard
                gesture.state == .ended,
                let tool = parent.annotationTool,
                tool == .check ||
                tool == .note ||
                tool == .currentRow ||
                tool == .eraser,
                let pdfView,
                let document = pdfView.document
            else {
                return
            }

            let location = gesture.location(in: pdfView)
            guard
                let page = pdfView.page(for: location, nearest: true),
                document.index(for: page) >= 0
            else {
                return
            }
            let pagePoint = pdfView.convert(location, to: page)
            let pageBounds = page.bounds(for: .cropBox)
            guard pageBounds.contains(pagePoint) else {
                return
            }

            if let selectedAnnotationID {
                if
                    let selected = selectedMovableAnnotation(
                        id: selectedAnnotationID,
                        at: pagePoint,
                        on: page,
                        in: document
                    ),
                    selected.type == .note
                {
                    parent.onNoteRequested(selected)
                    return
                }
                clearSelectedAnnotation()
                return
            }

            let annotation: PatternAnnotation?
            switch tool {
            case .check:
                if let existingCheck = existingCheckAnnotation(
                    at: pagePoint,
                    on: page,
                    in: document
                ) {
                    parent.onAnnotationDeleted(existingCheck)
                    return
                }
                annotation = makeCheckAnnotation(
                    at: location,
                    pagePoint: pagePoint,
                    page: page,
                    document: document
                )
            case .note:
                if let existingNote = existingNoteAnnotation(
                    at: pagePoint,
                    on: page,
                    in: document
                ) {
                    parent.onNoteRequested(existingNote)
                    return
                }
                if let noteAnnotation = makeNoteAnnotation(
                    at: location,
                    pagePoint: pagePoint,
                    page: page,
                    document: document
                ) {
                    parent.onNoteRequested(noteAnnotation)
                }
                annotation = nil
            case .currentRow:
                annotation = makeCurrentRowAnnotation(
                    at: location,
                    pagePoint: pagePoint,
                    page: page,
                    document: document
                )
            case .eraser:
                if let existingAnnotation = existingAnnotation(
                    at: pagePoint,
                    on: page,
                    in: document
                ) {
                    parent.onAnnotationDeleted(existingAnnotation)
                }
                annotation = nil
            case .highlight:
                annotation = nil
            }
            if let annotation {
                parent.onAnnotationCreated(annotation)
            }
        }

        private func beginMovingAnnotation(
            id: PatternAnnotation.ID,
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) {
            guard
                let annotation = selectedMovableAnnotation(
                    id: id,
                    at: pagePoint,
                    on: page,
                    in: document
                )
            else {
                clearMoveState()
                return
            }
            let pageBounds = page.bounds(for: .cropBox)
            let rect = annotation.bounds.rect(in: pageBounds)
            selectedAnnotationID = annotation.id
            movingAnnotation = annotation
            movingPage = page
            currentRowDragMode = dragMode(
                for: annotation,
                at: pagePoint,
                on: page
            )
            movingTouchOffset = CGPoint(
                x: pagePoint.x - rect.minX,
                y: pagePoint.y - rect.minY
            )
        }

        private func updateMovingAnnotation(
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument,
            shouldSave: Bool
        ) {
            guard
                let movingAnnotation,
                let movingPage,
                movingPage === page,
                let moved = movedAnnotation(
                    movingAnnotation,
                    to: pagePoint,
                    on: page,
                    in: document
                )
            else {
                if shouldSave {
                    clearMoveState()
                }
                return
            }

            currentAnnotations = currentAnnotations.map {
                $0.id == moved.id ? moved : $0
            }
            updateOverlay(for: moved.pageIndex)

            if shouldSave {
                clearMoveState()
                selectedAnnotationID = moved.id
                updateOverlay(for: moved.pageIndex)
                updateCurrentRowControls()
                parent.onAnnotationMoved(moved)
            }
        }

        private func movedAnnotation(
            _ annotation: PatternAnnotation,
            to pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PatternAnnotation? {
            let pageBounds = page.bounds(for: .cropBox)
            let originalRect = annotation.bounds.rect(in: pageBounds)
            let movedRect: CGRect

            if annotation.type == .currentRow {
                movedRect = currentRowRect(
                    from: originalRect,
                    axis: annotation.currentRowAxis,
                    pagePoint: pagePoint,
                    pageBounds: pageBounds
                )
            } else {
                let x = min(
                    max(
                        pageBounds.minX,
                        pagePoint.x - movingTouchOffset.x
                    ),
                    pageBounds.maxX - originalRect.width
                )
                let y = min(
                    max(
                        pageBounds.minY,
                        pagePoint.y - movingTouchOffset.y
                    ),
                    pageBounds.maxY - originalRect.height
                )
                movedRect = CGRect(
                    x: x,
                    y: y,
                    width: originalRect.width,
                    height: originalRect.height
                )
            }

            guard let movedBounds = NormalizedRect(rect: movedRect, in: pageBounds) else {
                return nil
            }
            return PatternAnnotation(
                id: annotation.id,
                type: annotation.type,
                pageIndex: document.index(for: page),
                bounds: movedBounds,
                highlightColor: annotation.highlightColor,
                highlightHex: annotation.highlightHex,
                points: annotation.points,
                normalizedLineWidth: annotation.normalizedLineWidth,
                createdAt: annotation.createdAt,
                noteText: annotation.noteText
            )
        }

        private func currentRowRect(
            from originalRect: CGRect,
            axis: CurrentRowAxis,
            pagePoint: CGPoint,
            pageBounds: CGRect
        ) -> CGRect {
            let minimumHorizontalThickness = pageBounds.height * 0.01
            let minimumVerticalThickness = pageBounds.width * 0.01

            switch (axis, currentRowDragMode) {
            case (.horizontal, .move):
                let y = min(
                    max(pageBounds.minY, pagePoint.y - movingTouchOffset.y),
                    pageBounds.maxY - originalRect.height
                )
                return CGRect(
                    x: pageBounds.minX,
                    y: y,
                    width: pageBounds.width,
                    height: originalRect.height
                )
            case (.horizontal, .resizeMinEdge):
                let minY = min(
                    max(pageBounds.minY, pagePoint.y),
                    originalRect.maxY - minimumHorizontalThickness
                )
                return CGRect(
                    x: pageBounds.minX,
                    y: minY,
                    width: pageBounds.width,
                    height: originalRect.maxY - minY
                )
            case (.horizontal, .resizeMaxEdge):
                let maxY = max(
                    min(pageBounds.maxY, pagePoint.y),
                    originalRect.minY + minimumHorizontalThickness
                )
                return CGRect(
                    x: pageBounds.minX,
                    y: originalRect.minY,
                    width: pageBounds.width,
                    height: maxY - originalRect.minY
                )
            case (.vertical, .move):
                let x = min(
                    max(pageBounds.minX, pagePoint.x - movingTouchOffset.x),
                    pageBounds.maxX - originalRect.width
                )
                return CGRect(
                    x: x,
                    y: pageBounds.minY,
                    width: originalRect.width,
                    height: pageBounds.height
                )
            case (.vertical, .resizeMinEdge):
                let minX = min(
                    max(pageBounds.minX, pagePoint.x),
                    originalRect.maxX - minimumVerticalThickness
                )
                return CGRect(
                    x: minX,
                    y: pageBounds.minY,
                    width: originalRect.maxX - minX,
                    height: pageBounds.height
                )
            case (.vertical, .resizeMaxEdge):
                let maxX = max(
                    min(pageBounds.maxX, pagePoint.x),
                    originalRect.minX + minimumVerticalThickness
                )
                return CGRect(
                    x: originalRect.minX,
                    y: pageBounds.minY,
                    width: maxX - originalRect.minX,
                    height: pageBounds.height
                )
            }
        }

        private func dragMode(
            for annotation: PatternAnnotation,
            at pagePoint: CGPoint,
            on page: PDFPage
        ) -> CurrentRowDragMode {
            guard annotation.type == .currentRow else {
                return .move
            }

            let pageBounds = page.bounds(for: .cropBox)
            let rect = annotation.bounds.rect(in: pageBounds)
            switch annotation.currentRowAxis {
            case .horizontal:
                let threshold = max(pageBounds.height * 0.012, rect.height * 0.35)
                if abs(pagePoint.y - rect.minY) <= threshold {
                    return .resizeMinEdge
                }
                if abs(pagePoint.y - rect.maxY) <= threshold {
                    return .resizeMaxEdge
                }
            case .vertical:
                let threshold = max(pageBounds.width * 0.012, rect.width * 0.35)
                if abs(pagePoint.x - rect.minX) <= threshold {
                    return .resizeMinEdge
                }
                if abs(pagePoint.x - rect.maxX) <= threshold {
                    return .resizeMaxEdge
                }
            }
            return .move
        }

        private func clearMoveState() {
            movingAnnotation = nil
            movingPage = nil
            movingTouchOffset = .zero
            currentRowDragMode = .move
        }

        private func clearSelectedAnnotation() {
            let previousID = selectedAnnotationID
            selectedAnnotationID = nil
            removeCurrentRowControls()
            guard
                let previousID,
                let previousPageIndex = currentAnnotations.first(
                    where: { $0.id == previousID }
                )?.pageIndex
            else {
                for pageIndex in visibleOverlays.keys {
                    updateOverlay(for: pageIndex)
                }
                return
            }
            updateOverlay(for: previousPageIndex)
        }

        private func updateOverlay(for pageIndex: Int) {
            guard let overlay = visibleOverlays[pageIndex] else {
                return
            }
            overlay.annotations = showsAnnotations
                ? currentAnnotations.filter { $0.pageIndex == pageIndex }
                : []
            overlay.selectedAnnotationID = selectedAnnotationID
            updateCurrentRowControls()
        }

        private func existingNoteAnnotation(
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PatternAnnotation? {
            let pageIndex = document.index(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            return currentAnnotations
                .filter { $0.type == .note && $0.pageIndex == pageIndex }
                .reversed()
                .first {
                    $0.bounds
                        .rect(in: pageBounds)
                        .insetBy(dx: -10, dy: -10)
                        .contains(pagePoint)
                }
        }

        private func existingMovableAnnotation(
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PatternAnnotation? {
            let pageIndex = document.index(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            return currentAnnotations
                .filter {
                    $0.pageIndex == pageIndex &&
                    ($0.type == .check || $0.type == .note || $0.type == .currentRow)
                }
                .reversed()
                .first {
                    $0.bounds
                        .rect(in: pageBounds)
                        .insetBy(dx: -12, dy: -12)
                        .contains(pagePoint)
                }
        }

        private func selectedMovableAnnotation(
            id: PatternAnnotation.ID,
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PatternAnnotation? {
            let pageIndex = document.index(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            return currentAnnotations
                .first {
                    $0.id == id &&
                    $0.pageIndex == pageIndex &&
                    ($0.type == .check || $0.type == .note || $0.type == .currentRow) &&
                    $0.bounds
                        .rect(in: pageBounds)
                        .insetBy(dx: -12, dy: -12)
                        .contains(pagePoint)
                }
        }

        private func existingAnnotation(
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PatternAnnotation? {
            let pageIndex = document.index(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            return currentAnnotations
                .filter { $0.pageIndex == pageIndex }
                .reversed()
                .first {
                    $0.bounds
                        .rect(in: pageBounds)
                        .insetBy(dx: -10, dy: -10)
                        .contains(pagePoint)
                }
        }

        private func existingCheckAnnotation(
            at pagePoint: CGPoint,
            on page: PDFPage,
            in document: PDFDocument
        ) -> PatternAnnotation? {
            let pageIndex = document.index(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            return currentAnnotations
                .filter { $0.type == .check && $0.pageIndex == pageIndex }
                .reversed()
                .first {
                    $0.bounds
                        .rect(in: pageBounds)
                        .insetBy(dx: -8, dy: -8)
                        .contains(pagePoint)
                }
        }

        private func selectedCurrentRow() -> (annotation: PatternAnnotation, page: PDFPage)? {
            guard
                showsAnnotations,
                let selectedAnnotationID,
                let pdfView,
                let document = pdfView.document,
                let annotation = currentAnnotations.first(where: {
                    $0.id == selectedAnnotationID && $0.type == .currentRow
                }),
                let page = document.page(at: annotation.pageIndex)
            else {
                return nil
            }
            return (annotation, page)
        }

        private func updateCurrentRowControls() {
            guard
                let pdfView,
                let selected = selectedCurrentRow()
            else {
                removeCurrentRowControls()
                return
            }

            let controlView: CurrentRowControlView
            if let currentRowControlView {
                controlView = currentRowControlView
            } else {
                let view = CurrentRowControlView()
                view.onPrevious = { [weak self] in
                    self?.moveSelectedCurrentRowByStep(.previous)
                }
                view.onNext = { [weak self] in
                    self?.moveSelectedCurrentRowByStep(.next)
                }
                pdfView.addSubview(view)
                currentRowControlView = view
                controlView = view
            }

            let viewRect = viewRect(
                for: selected.annotation,
                on: selected.page,
                in: pdfView
            )
            let size = CGSize(width: 132, height: 38)
            let preferredY = viewRect.minY - size.height - 8
            let fallbackY = viewRect.maxY + 8
            let maxY = max(8, pdfView.bounds.maxY - size.height - 8)
            let unclampedY = preferredY >= 8 ? preferredY : fallbackY
            let y = min(max(8, unclampedY), maxY)
            let maxX = max(8, pdfView.bounds.maxX - size.width - 8)
            let x = min(
                max(8, viewRect.midX - (size.width / 2)),
                maxX
            )
            controlView.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        }

        private func removeCurrentRowControls() {
            currentRowControlView?.removeFromSuperview()
            currentRowControlView = nil
        }

        private func moveSelectedCurrentRowByStep(_ direction: CurrentRowStepDirection) {
            guard
                let selected = selectedCurrentRow(),
                let pdfView,
                let document = pdfView.document
            else {
                return
            }

            let pageBounds = selected.page.bounds(for: .cropBox)
            let rect = selected.annotation.bounds.rect(in: pageBounds)
            let movedRect: CGRect
            switch (selected.annotation.currentRowAxis, direction) {
            case (.horizontal, .previous):
                movedRect = CGRect(
                    x: pageBounds.minX,
                    y: max(pageBounds.minY, rect.minY - rect.height),
                    width: pageBounds.width,
                    height: rect.height
                )
            case (.horizontal, .next):
                movedRect = CGRect(
                    x: pageBounds.minX,
                    y: min(pageBounds.maxY - rect.height, rect.minY + rect.height),
                    width: pageBounds.width,
                    height: rect.height
                )
            case (.vertical, .previous):
                movedRect = CGRect(
                    x: max(pageBounds.minX, rect.minX - rect.width),
                    y: pageBounds.minY,
                    width: rect.width,
                    height: pageBounds.height
                )
            case (.vertical, .next):
                movedRect = CGRect(
                    x: min(pageBounds.maxX - rect.width, rect.minX + rect.width),
                    y: pageBounds.minY,
                    width: rect.width,
                    height: pageBounds.height
                )
            }

            guard let movedBounds = NormalizedRect(rect: movedRect, in: pageBounds) else {
                return
            }
            let moved = PatternAnnotation(
                id: selected.annotation.id,
                type: selected.annotation.type,
                pageIndex: document.index(for: selected.page),
                bounds: movedBounds,
                highlightColor: selected.annotation.highlightColor,
                highlightHex: selected.annotation.highlightHex,
                points: selected.annotation.points,
                normalizedLineWidth: selected.annotation.normalizedLineWidth,
                createdAt: selected.annotation.createdAt,
                noteText: selected.annotation.noteText
            )

            currentAnnotations = currentAnnotations.map {
                $0.id == moved.id ? moved : $0
            }
            updateOverlay(for: moved.pageIndex)
            updateCurrentRowControls()
            parent.onAnnotationMoved(moved)
        }

        private func viewRect(
            for annotation: PatternAnnotation,
            on page: PDFPage,
            in pdfView: PDFView
        ) -> CGRect {
            let pageBounds = page.bounds(for: .cropBox)
            let rect = annotation.bounds.rect(in: pageBounds)
            let points = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ].map { pdfView.convert($0, from: page) }
            return points.reduce(CGRect.null) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        }

        @objc func handleHighlightGesture(_ gesture: UIPanGestureRecognizer) {
            guard
                parent.annotationTool == .highlight,
                let pdfView,
                let document = pdfView.document
            else {
                return
            }

            let location = gesture.location(in: pdfView)

            switch gesture.state {
            case .began:
                guard
                    let page = pdfView.page(for: location, nearest: true),
                    document.index(for: page) >= 0
                else {
                    return
                }
                let pagePoint = pdfView.convert(location, to: page)
                guard page.bounds(for: .cropBox).contains(pagePoint) else {
                    return
                }

                let id = UUID()
                let draft = HighlightStrokeDraftView(frame: pdfView.bounds)
                draft.isUserInteractionEnabled = false
                draft.isOpaque = false
                draft.backgroundColor = .clear
                draft.contentMode = .redraw
                draft.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                draft.strokeColor = UIColor(highlightHex: parent.highlightHex)
                draft.lineWidth = HighlightDrawing.viewLineWidth
                draft.points = [location]
                activePage = page
                draftViewPoints = [location]
                draftView = draft
                draftID = id
                pdfView.addSubview(draft)

            case .changed:
                appendDraftPoint(location)

            case .ended:
                appendDraftPoint(location)
                finishDraft(in: document)

            case .cancelled, .failed:
                removeDraft()

            default:
                break
            }
        }

        private func appendDraftPoint(_ viewPoint: CGPoint) {
            guard
                let pdfView,
                let page = activePage,
                let draftView
            else {
                return
            }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            guard page.bounds(for: .cropBox).contains(pagePoint) else {
                return
            }

            if
                let lastPoint = draftViewPoints.last,
                hypot(viewPoint.x - lastPoint.x, viewPoint.y - lastPoint.y) < 1.5
            {
                return
            }
            draftViewPoints.append(viewPoint)
            draftView.points = draftViewPoints
        }

        private func finishDraft(in document: PDFDocument) {
            guard
                let pdfView,
                let page = activePage,
                let draftView,
                let draftID,
                draftViewPoints.count >= 2
            else {
                removeDraft()
                return
            }

            let pageBounds = page.bounds(for: .cropBox)
            let pagePoints = draftViewPoints.map { pdfView.convert($0, to: page) }
            let normalizedPoints = pagePoints.compactMap {
                NormalizedPoint(point: $0, in: pageBounds)
            }
            let pageStrokeWidth = pageLineWidth(
                at: draftViewPoints[0],
                on: page
            )
            let pathBounds = pagePoints.reduce(CGRect.null) {
                $0.union(CGRect(origin: $1, size: .zero))
            }.insetBy(
                dx: -(pageStrokeWidth / 2),
                dy: -(pageStrokeWidth / 2)
            )

            guard
                normalizedPoints.count >= 2,
                pageStrokeWidth > 0,
                let normalizedBounds = NormalizedRect(
                    rect: pathBounds,
                    in: pageBounds
                )
            else {
                removeDraft()
                return
            }

            let pageIndex = document.index(for: page)
            let annotation = PatternAnnotation(
                id: draftID,
                type: .highlight,
                pageIndex: pageIndex,
                bounds: normalizedBounds,
                highlightColor: nil,
                highlightHex: parent.highlightHex,
                points: normalizedPoints,
                normalizedLineWidth: pageStrokeWidth / pageBounds.width,
                createdAt: Date()
            )

            draftView.removeFromSuperview()
            clearDraftState()
            parent.onAnnotationCreated(annotation)
        }

        private func removeDraft() {
            draftView?.removeFromSuperview()
            clearDraftState()
        }

        private func clearDraftState() {
            activePage = nil
            draftViewPoints = []
            draftView = nil
            draftID = nil
        }

        private func pageLineWidth(at viewPoint: CGPoint, on page: PDFPage) -> CGFloat {
            guard let pdfView else {
                return 0
            }
            let start = pdfView.convert(viewPoint, to: page)
            let end = pdfView.convert(
                CGPoint(x: viewPoint.x + HighlightDrawing.viewLineWidth, y: viewPoint.y),
                to: page
            )
            return hypot(end.x - start.x, end.y - start.y)
        }

        private func makeCheckAnnotation(
            at viewPoint: CGPoint,
            pagePoint: CGPoint,
            page: PDFPage,
            document: PDFDocument
        ) -> PatternAnnotation? {
            let pageBounds = page.bounds(for: .cropBox)
            let size = pageSize(forViewSize: 30, at: viewPoint, on: page)
            let rect = CGRect(
                x: pagePoint.x - (size.width / 2),
                y: pagePoint.y - (size.height / 2),
                width: size.width,
                height: size.height
            )
            guard let bounds = NormalizedRect(rect: rect, in: pageBounds) else {
                return nil
            }
            return PatternAnnotation(
                id: UUID(),
                type: .check,
                pageIndex: document.index(for: page),
                bounds: bounds,
                highlightColor: nil,
                highlightHex: nil,
                points: nil,
                normalizedLineWidth: nil,
                createdAt: Date()
            )
        }

        private func makeCurrentRowAnnotation(
            at viewPoint: CGPoint,
            pagePoint: CGPoint,
            page: PDFPage,
            document: PDFDocument
        ) -> PatternAnnotation? {
            let pageBounds = page.bounds(for: .cropBox)
            let axis = parent.currentRowAxis
            let size = pageSize(forViewSize: 26, at: viewPoint, on: page)
            let rect: CGRect
            switch axis {
            case .horizontal:
                rect = CGRect(
                    x: pageBounds.minX,
                    y: pagePoint.y - (size.height / 2),
                    width: pageBounds.width,
                    height: size.height
                )
            case .vertical:
                rect = CGRect(
                    x: pagePoint.x - (size.width / 2),
                    y: pageBounds.minY,
                    width: size.width,
                    height: pageBounds.height
                )
            }
            guard let bounds = NormalizedRect(rect: rect, in: pageBounds) else {
                return nil
            }
            return PatternAnnotation(
                id: UUID(),
                type: .currentRow,
                pageIndex: document.index(for: page),
                bounds: bounds,
                highlightColor: nil,
                highlightHex: nil,
                points: nil,
                normalizedLineWidth: nil,
                createdAt: Date(),
                noteText: PatternAnnotation.currentRowAxisNoteText(axis)
            )
        }

        private func makeNoteAnnotation(
            at viewPoint: CGPoint,
            pagePoint: CGPoint,
            page: PDFPage,
            document: PDFDocument
        ) -> PatternAnnotation? {
            let pageBounds = page.bounds(for: .cropBox)
            let size = pageSize(forViewSize: 32, at: viewPoint, on: page)
            let rect = CGRect(
                x: pagePoint.x - (size.width / 2),
                y: pagePoint.y - (size.height / 2),
                width: size.width,
                height: size.height
            )
            guard let bounds = NormalizedRect(rect: rect, in: pageBounds) else {
                return nil
            }
            return PatternAnnotation(
                id: UUID(),
                type: .note,
                pageIndex: document.index(for: page),
                bounds: bounds,
                highlightColor: nil,
                highlightHex: nil,
                points: nil,
                normalizedLineWidth: nil,
                createdAt: Date()
            )
        }

        private func pageSize(
            forViewSize viewSize: CGFloat,
            at viewPoint: CGPoint,
            on page: PDFPage
        ) -> CGSize {
            guard let pdfView else {
                return .zero
            }
            let start = pdfView.convert(viewPoint, to: page)
            let end = pdfView.convert(
                CGPoint(x: viewPoint.x + viewSize, y: viewPoint.y + viewSize),
                to: page
            )
            return CGSize(
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }
    }
}

private enum HighlightDrawing {
    static let viewLineWidth: CGFloat = 18

    static func path(points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        guard points.count > 1 else {
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: midpoint, controlPoint: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }
}

private final class HighlightStrokeDraftView: UIView {
    var points: [CGPoint] = [] {
        didSet { setNeedsDisplay() }
    }
    var strokeColor: UIColor = UIColor(highlightHex: "F1C878")
    var lineWidth: CGFloat = HighlightDrawing.viewLineWidth

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.clear(bounds)
        context.saveGState()
        context.setBlendMode(.normal)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(HighlightDrawing.path(points: points).cgPath)
        context.strokePath()
        context.restoreGState()
    }
}

private final class HighlightPageOverlayView: UIView {
    var annotations: [PatternAnnotation] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    var selectedAnnotationID: PatternAnnotation.ID? {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.clear(bounds)
        context.saveGState()
        context.setBlendMode(.normal)
        for annotation in annotations {
            if annotation.id == selectedAnnotationID {
                drawSelection(for: annotation, in: context)
            }
            switch annotation.type {
            case .highlight where annotation.isFreehandHighlight:
                let color = UIColor(highlightHex: annotation.resolvedHighlightHex)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(
                    CGFloat(annotation.normalizedLineWidth ?? 0) * bounds.width
                )
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(
                    HighlightDrawing.path(
                        points: annotation.viewPoints(in: bounds)
                    ).cgPath
                )
                context.strokePath()
            case .highlight:
                let color = UIColor(highlightHex: annotation.resolvedHighlightHex)
                context.setFillColor(color.cgColor)
                context.fill(annotation.viewRect(in: bounds))
            case .check:
                drawCheck(annotation, in: context)
            case .note:
                drawNote(annotation, in: context)
            case .currentRow:
                context.setFillColor(
                    UIColor(
                        red: 221 / 255,
                        green: 235 / 255,
                        blue: 134 / 255,
                        alpha: 0.48
                    ).cgColor
                )
                context.fill(annotation.currentRowRect(in: bounds))
            }
        }
        context.restoreGState()
    }

    private func drawSelection(
        for annotation: PatternAnnotation,
        in context: CGContext
    ) {
        let selectionRect: CGRect
        switch annotation.type {
        case .check:
            selectionRect = annotation.fixedCheckRect(
                in: bounds,
                size: AnnotationDrawing.checkSize
            ).insetBy(dx: -6, dy: -6)
        case .note:
            selectionRect = annotation.fixedCheckRect(
                in: bounds,
                size: AnnotationDrawing.noteSize
            ).insetBy(dx: -6, dy: -6)
        case .currentRow:
            selectionRect = annotation.currentRowRect(in: bounds)
                .insetBy(dx: 5, dy: -5)
        case .highlight:
            return
        }

        context.saveGState()
        let fillColor: UIColor = switch annotation.type {
        case .currentRow:
            UIColor(YDColor.yarn1.opacity(0.16))
        default:
            UIColor(YDColor.wood1.opacity(0.24))
        }
        context.setFillColor(fillColor.cgColor)
        let path = UIBezierPath(
            roundedRect: selectionRect,
            cornerRadius: min(12, selectionRect.height / 2)
        )
        context.addPath(path.cgPath)
        context.fillPath()
        if annotation.type == .currentRow {
            drawCurrentRowHandles(for: annotation, in: context)
        }
        context.restoreGState()
    }

    private func drawCurrentRowHandles(
        for annotation: PatternAnnotation,
        in context: CGContext
    ) {
        let rowRect = annotation.currentRowRect(in: bounds)
        let handleColor = UIColor(YDColor.yarn4.opacity(0.86)).cgColor
        context.setFillColor(handleColor)

        switch annotation.currentRowAxis {
        case .horizontal:
            let width = min(88, max(38, rowRect.width * 0.18))
            let height: CGFloat = 4
            for y in [rowRect.minY, rowRect.maxY] {
                let rect = CGRect(
                    x: rowRect.midX - (width / 2),
                    y: y - (height / 2),
                    width: width,
                    height: height
                )
                let path = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
                context.addPath(path.cgPath)
                context.fillPath()
            }
        case .vertical:
            let width: CGFloat = 4
            let height = min(88, max(38, rowRect.height * 0.18))
            for x in [rowRect.minX, rowRect.maxX] {
                let rect = CGRect(
                    x: x - (width / 2),
                    y: rowRect.midY - (height / 2),
                    width: width,
                    height: height
                )
                let path = UIBezierPath(roundedRect: rect, cornerRadius: width / 2)
                context.addPath(path.cgPath)
                context.fillPath()
            }
        }
    }

    private func drawCheck(
        _ annotation: PatternAnnotation,
        in context: CGContext
    ) {
        let circleRect = annotation.fixedCheckRect(
            in: bounds,
            size: AnnotationDrawing.checkSize
        )
        context.setFillColor(UIColor(YDColor.yarn4).cgColor)
        context.fillEllipse(in: circleRect)

        let path = UIBezierPath()
        path.move(
            to: CGPoint(
                x: circleRect.minX + circleRect.width * 0.25,
                y: circleRect.midY
            )
        )
        path.addLine(
            to: CGPoint(
                x: circleRect.minX + circleRect.width * 0.43,
                y: circleRect.maxY - circleRect.height * 0.28
            )
        )
        path.addLine(
            to: CGPoint(
                x: circleRect.maxX - circleRect.width * 0.20,
                y: circleRect.minY + circleRect.height * 0.28
            )
        )
        context.setStrokeColor(UIColor(YDColor.cream0).cgColor)
        context.setLineWidth(max(2, circleRect.width * 0.11))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPath)
        context.strokePath()
    }

    private func drawNote(
        _ annotation: PatternAnnotation,
        in context: CGContext
    ) {
        let rect = annotation.fixedCheckRect(
            in: bounds,
            size: AnnotationDrawing.noteSize
        )
        let bubbleRect = rect.insetBy(
            dx: rect.width * 0.10,
            dy: rect.height * 0.12
        )
        let tailPoint = CGPoint(
            x: bubbleRect.minX + bubbleRect.width * 0.24,
            y: bubbleRect.maxY + rect.height * 0.14
        )
        let bubblePath = UIBezierPath(
            roundedRect: bubbleRect,
            cornerRadius: bubbleRect.width * 0.32
        )
        bubblePath.move(
            to: CGPoint(
                x: bubbleRect.minX + bubbleRect.width * 0.24,
                y: bubbleRect.maxY - bubbleRect.height * 0.12
            )
        )
        bubblePath.addLine(to: tailPoint)
        bubblePath.addLine(
            to: CGPoint(
                x: bubbleRect.minX + bubbleRect.width * 0.42,
                y: bubbleRect.maxY - bubbleRect.height * 0.04
            )
        )
        bubblePath.close()

        context.setFillColor(UIColor(YDColor.wood1.opacity(0.92)).cgColor)
        context.addPath(bubblePath.cgPath)
        context.fillPath()

        context.setStrokeColor(UIColor(YDColor.wood3.opacity(0.72)).cgColor)
        context.setLineWidth(max(1.2, rect.width * 0.055))
        context.setLineJoin(.round)
        context.addPath(bubblePath.cgPath)
        context.strokePath()

        context.setFillColor(UIColor(YDColor.wood3.opacity(0.72)).cgColor)
        let dotSize = max(2.2, rect.width * 0.09)
        let dotY = bubbleRect.midY - (dotSize / 2)
        for offset in [-0.16, 0, 0.16] {
            let dotRect = CGRect(
                x: bubbleRect.midX + (bubbleRect.width * CGFloat(offset)) - (dotSize / 2),
                y: dotY,
                width: dotSize,
                height: dotSize
            )
            context.fillEllipse(in: dotRect)
        }
    }
}

private enum AnnotationDrawing {
    static let checkSize: CGFloat = 28
    static let noteSize: CGFloat = 28
}

private enum CurrentRowDragMode {
    case move
    case resizeMinEdge
    case resizeMaxEdge
}

private enum CurrentRowStepDirection {
    case previous
    case next
}

private final class CurrentRowControlView: UIView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = UIColor(YDColor.ink.opacity(0.94))
        layer.cornerRadius = 14
        layer.masksToBounds = true

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 1
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        let previousButton = makeButton(title: "이전", action: #selector(handlePrevious))
        let nextButton = makeButton(title: "이후", action: #selector(handleNext))
        stackView.addArrangedSubview(previousButton)
        stackView.addArrangedSubview(nextButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIColor(YDColor.cream0), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        button.backgroundColor = UIColor.clear
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func handlePrevious() {
        onPrevious?()
    }

    @objc private func handleNext() {
        onNext?()
    }
}

private extension UIColor {
    convenience init(highlightHex hex: String) {
        let sanitized = String(hex.filter(\.isHexDigit).prefix(6))
        let value = UInt64(sanitized, radix: 16) ?? 0xF1C878
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 0.48
        )
    }
}

private extension PatternAnnotation {
    func viewPoints(in overlayBounds: CGRect) -> [CGPoint] {
        (points ?? []).map {
            CGPoint(
                x: $0.x * overlayBounds.width,
                y: (1 - $0.y) * overlayBounds.height
            )
        }
    }

    func viewRect(in overlayBounds: CGRect) -> CGRect {
        let normalized = bounds
        return CGRect(
            x: normalized.x * overlayBounds.width,
            y: (1 - normalized.y - normalized.height) * overlayBounds.height,
            width: normalized.width * overlayBounds.width,
            height: normalized.height * overlayBounds.height
        )
    }

    func fixedCheckRect(in overlayBounds: CGRect, size: CGFloat) -> CGRect {
        let rect = viewRect(in: overlayBounds)
        return CGRect(
            x: rect.midX - (size / 2),
            y: rect.midY - (size / 2),
            width: size,
            height: size
        )
    }

    func currentRowRect(in overlayBounds: CGRect) -> CGRect {
        let rect = viewRect(in: overlayBounds)
        switch currentRowAxis {
        case .horizontal:
            return CGRect(
                x: 0,
                y: rect.minY,
                width: overlayBounds.width,
                height: max(1, rect.height)
            )
        case .vertical:
            return CGRect(
                x: rect.minX,
                y: 0,
                width: max(1, rect.width),
                height: overlayBounds.height
            )
        }
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
