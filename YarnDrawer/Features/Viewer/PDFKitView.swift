import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let annotations: [PatternAnnotation]
    let annotationTool: PDFAnnotationTool?
    let showsAnnotations: Bool
    let highlightHex: String
    let initialPageIndex: Int
    let onAnnotationCreated: (PatternAnnotation) -> Void
    let onPageChanged: (Int) -> Void

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

        context.coordinator.pdfView = view
        context.coordinator.highlightGesture = highlightGesture
        context.coordinator.placementGesture = placementGesture
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
                initialPageIndex: initialPageIndex
            )
        }

        context.coordinator.highlightGesture?.isEnabled = annotationTool == .highlight
        context.coordinator.placementGesture?.isEnabled =
            annotationTool == .check || annotationTool == .currentRow
        context.coordinator.configureScrolling(for: annotationTool == .highlight)
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PDFViewDelegate {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        weak var highlightGesture: UIPanGestureRecognizer?
        weak var placementGesture: UITapGestureRecognizer?

        private var activePage: PDFPage?
        private var draftViewPoints: [CGPoint] = []
        private weak var draftView: HighlightStrokeDraftView?
        private var draftID: UUID?
        private var currentAnnotations: [PatternAnnotation]
        private var showsAnnotations: Bool
        private var visibleOverlays: [Int: HighlightPageOverlayView] = [:]
        private var isRestoringPage = false

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
        }

        func loadDocument(from url: URL, initialPageIndex: Int) {
            guard
                let pdfView,
                let document = PDFDocument(url: url),
                document.pageCount > 0
            else {
                return
            }
            isRestoringPage = true
            pdfView.document = document
            let safeIndex = min(max(0, initialPageIndex), document.pageCount - 1)
            guard let page = document.page(at: safeIndex) else {
                isRestoringPage = false
                return
            }
            pdfView.go(to: page)
            DispatchQueue.main.async { [weak self] in
                self?.isRestoringPage = false
                self?.handlePageChanged()
            }
        }

        func configureScrolling(for isHighlighting: Bool) {
            guard let scrollView = pdfView?.firstDescendant(of: UIScrollView.self) else {
                return
            }
            scrollView.panGestureRecognizer.minimumNumberOfTouches = isHighlighting ? 2 : 1
        }

        func syncAnnotations(
            _ annotations: [PatternAnnotation],
            showsAnnotations: Bool
        ) {
            currentAnnotations = annotations
            self.showsAnnotations = showsAnnotations

            for (pageIndex, overlay) in visibleOverlays {
                overlay.annotations = showsAnnotations
                    ? annotations.filter { $0.pageIndex == pageIndex }
                    : []
            }
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
            parent.onPageChanged(pageIndex)
        }

        @objc func handlePlacementGesture(_ gesture: UITapGestureRecognizer) {
            guard
                gesture.state == .ended,
                let tool = parent.annotationTool,
                tool == .check || tool == .currentRow,
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

            let annotation: PatternAnnotation?
            switch tool {
            case .check:
                annotation = makeCheckAnnotation(
                    at: location,
                    pagePoint: pagePoint,
                    page: page,
                    document: document
                )
            case .currentRow:
                annotation = makeCurrentRowAnnotation(
                    at: location,
                    pagePoint: pagePoint,
                    page: page,
                    document: document
                )
            case .highlight:
                annotation = nil
            }
            if let annotation {
                parent.onAnnotationCreated(annotation)
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
            let height = pageSize(forViewSize: 26, at: viewPoint, on: page).height
            let rect = CGRect(
                x: pageBounds.minX,
                y: pagePoint.y - (height / 2),
                width: pageBounds.width,
                height: height
            )
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

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.clear(bounds)
        context.saveGState()
        context.setBlendMode(.normal)
        for annotation in annotations {
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
            case .currentRow:
                context.setFillColor(
                    UIColor(
                        red: 221 / 255,
                        green: 235 / 255,
                        blue: 134 / 255,
                        alpha: 0.48
                    ).cgColor
                )
                context.fill(annotation.viewRect(in: bounds))
            }
        }
        context.restoreGState()
    }

    private func drawCheck(
        _ annotation: PatternAnnotation,
        in context: CGContext
    ) {
        let rect = annotation.viewRect(in: bounds)
        let circleRect = rect.insetBy(
            dx: rect.width * 0.08,
            dy: rect.height * 0.08
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
