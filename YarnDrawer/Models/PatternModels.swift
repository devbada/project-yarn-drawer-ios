import Foundation

enum CraftType: String, Codable, CaseIterable, Identifiable {
    case knitting
    case crochet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .knitting: "대바늘"
        case .crochet: "코바늘"
        }
    }
}

enum SourceFileType: String, Codable {
    case pdf
    case jpg
    case jpeg
    case png

    var isImage: Bool {
        self != .pdf
    }
}

enum FileAssetPurpose: String, Codable {
    case original
    case viewPDF
    case thumbnail
}

struct FileAsset: Codable, Identifiable, Hashable {
    let id: UUID
    let purpose: FileAssetPurpose
    let storageKey: String
    let mimeType: String
    let byteSize: Int64
    let checksumSHA256: String
    let derivedFromAssetID: UUID?
    let createdAt: Date
}

enum PatternAnnotationType: String, Codable {
    case highlight
    case check
    case currentRow
}

enum PDFAnnotationTool {
    case highlight
    case check
    case currentRow
}

enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case coral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: "노랑"
        case .green: "연두"
        case .blue: "파랑"
        case .coral: "코랄"
        }
    }
}

struct HighlightInk: Codable, Hashable, Identifiable {
    let hex: String
    let title: String

    var id: String { hex }

    init(hex: String, title: String) {
        self.hex = String(hex.filter(\.isHexDigit).prefix(6)).uppercased()
        self.title = title
    }

    static let presets: [HighlightInk] = [
        HighlightInk(hex: "F1C878", title: "노랑"),
        HighlightInk(hex: "DDEB86", title: "연두"),
        HighlightInk(hex: "80E5D2", title: "민트"),
        HighlightInk(hex: "7DD3FC", title: "하늘"),
        HighlightInk(hex: "A5B4FC", title: "파랑"),
        HighlightInk(hex: "C4B5FD", title: "보라"),
        HighlightInk(hex: "F9A8D4", title: "분홍"),
        HighlightInk(hex: "FDA4AF", title: "장미"),
        HighlightInk(hex: "FDBA74", title: "주황"),
        HighlightInk(hex: "D1D5DB", title: "회색")
    ]
}

struct NormalizedRect: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init?(rect: CGRect, in pageBounds: CGRect) {
        guard
            pageBounds.width > 0,
            pageBounds.height > 0
        else {
            return nil
        }

        let clipped = rect.standardized.intersection(pageBounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }

        x = (clipped.minX - pageBounds.minX) / pageBounds.width
        y = (clipped.minY - pageBounds.minY) / pageBounds.height
        width = clipped.width / pageBounds.width
        height = clipped.height / pageBounds.height
    }

    func rect(in pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.minX + (x * pageBounds.width),
            y: pageBounds.minY + (y * pageBounds.height),
            width: width * pageBounds.width,
            height: height * pageBounds.height
        )
    }
}

struct NormalizedPoint: Codable, Hashable {
    let x: Double
    let y: Double

    init?(point: CGPoint, in pageBounds: CGRect) {
        guard
            pageBounds.width > 0,
            pageBounds.height > 0,
            pageBounds.contains(point)
        else {
            return nil
        }
        x = (point.x - pageBounds.minX) / pageBounds.width
        y = (point.y - pageBounds.minY) / pageBounds.height
    }

    func point(in pageBounds: CGRect) -> CGPoint {
        CGPoint(
            x: pageBounds.minX + (x * pageBounds.width),
            y: pageBounds.minY + (y * pageBounds.height)
        )
    }
}

struct PatternAnnotation: Codable, Identifiable, Hashable {
    let id: UUID
    let type: PatternAnnotationType
    let pageIndex: Int
    let bounds: NormalizedRect
    let highlightColor: HighlightColor?
    let highlightHex: String?
    let points: [NormalizedPoint]?
    let normalizedLineWidth: Double?
    let createdAt: Date

    var resolvedHighlightColor: HighlightColor {
        highlightColor ?? .yellow
    }

    var resolvedHighlightHex: String {
        if let highlightHex, highlightHex.count == 6 {
            return highlightHex
        }
        return switch resolvedHighlightColor {
        case .yellow: "F1C878"
        case .green: "DDEB86"
        case .blue: "246BCE"
        case .coral: "9B4E2C"
        }
    }

    var isFreehandHighlight: Bool {
        (points?.count ?? 0) >= 2 && (normalizedLineWidth ?? 0) > 0
    }
}

struct PatternViewerState: Codable, Equatable {
    let patternID: UUID
    var lastPageIndex: Int
    var updatedAt: Date
}

struct PatternGaugeInfo: Codable, Hashable {
    var stitches: Double?
    var rows: Double?
    var measurementLengthCM: Double?

    var isEmpty: Bool {
        stitches == nil && rows == nil && measurementLengthCM == nil
    }
}

struct PatternMaterialInfo: Codable, Hashable {
    var yarnName: String?
    var yarnWeight: String?
    var needleSizeMM: Double?
    var hookSizeMM: Double?

    var isEmpty: Bool {
        yarnName == nil &&
            yarnWeight == nil &&
            needleSizeMM == nil &&
            hookSizeMM == nil
    }
}

struct PatternItem: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var designerName: String?
    var craftType: CraftType
    var sourceFileType: SourceFileType
    var originalAsset: FileAsset?
    var viewAsset: FileAsset?
    var originalFileName: String
    var pageCount: Int
    var tags: [String]
    var isFavorite: Bool
    var progress: Double
    var lastOpenedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var thumbnailStyle: PatternThumbnailStyle
    var symbol: String
    var isSample: Bool
    var gaugeInfo: PatternGaugeInfo? = nil
    var materialInfo: PatternMaterialInfo? = nil
    var notes: String? = nil

    var searchableText: String {
        (
            [
                title,
                designerName ?? "",
                craftType.title,
                materialInfo?.yarnName ?? "",
                materialInfo?.yarnWeight ?? ""
            ] + tags
        )
            .joined(separator: " ")
            .localizedLowercase
    }

    var metadataLine: String {
        let designer = designerName?.isEmpty == false ? designerName! : "작가 미상"
        let opened = lastOpenedAt?.formatted(.relative(presentation: .named)) ?? "아직 열지 않음"
        return "\(designer) · \(craftType.title) · \(opened)"
    }

    var fileBadge: String {
        if sourceFileType.isImage {
            return "\(sourceFileType.rawValue.uppercased()) → PDF"
        }
        if progress >= 1 {
            return "PDF · 완료"
        }
        return "PDF · 편집 중"
    }
}

enum PatternThumbnailStyle: String, Codable {
    case green
    case cream
    case wood
}

struct PatternImportDraft {
    var sourceURL: URL
    var title: String
    var designerName: String
    var craftType: CraftType
    var tagsText: String

    var tags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for component in tagsText.split(separator: ",") {
            let tag = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !tag.isEmpty,
                seen.insert(tag.localizedLowercase).inserted
            else {
                continue
            }
            result.append(tag)
            if result.count == 10 {
                break
            }
        }
        return result
    }
}

extension PatternItem {
    static let samples: [PatternItem] = [
        PatternItem(
            id: UUID(uuidString: "2C1BD381-9A47-4EDB-B486-A6BBA177683D")!,
            title: "브라운 울 가디건",
            designerName: "knit.mori",
            craftType: .knitting,
            sourceFileType: .pdf,
            originalAsset: nil,
            viewAsset: nil,
            originalFileName: "brown-wool-cardigan.pdf",
            pageCount: 8,
            tags: ["가디건", "메리노 울"],
            isFavorite: true,
            progress: 0.62,
            lastOpenedAt: Date().addingTimeInterval(-600),
            createdAt: Date().addingTimeInterval(-86_400 * 14),
            updatedAt: Date(),
            thumbnailStyle: .green,
            symbol: "V",
            isSample: true
        ),
        PatternItem(
            id: UUID(uuidString: "767AD4CA-9DA7-4672-A91C-04DC937284C3")!,
            title: "여름 레이스 탑",
            designerName: "studio loop",
            craftType: .crochet,
            sourceFileType: .jpg,
            originalAsset: nil,
            viewAsset: nil,
            originalFileName: "summer-lace.jpg",
            pageCount: 1,
            tags: ["레이스", "코튼"],
            isFavorite: false,
            progress: 0.28,
            lastOpenedAt: Date().addingTimeInterval(-86_400),
            createdAt: Date().addingTimeInterval(-86_400 * 7),
            updatedAt: Date(),
            thumbnailStyle: .cream,
            symbol: "○",
            isSample: true
        ),
        PatternItem(
            id: UUID(uuidString: "674F3972-876B-4AB0-BC58-C0BD7FA5A322")!,
            title: "노르딕 양말",
            designerName: "sock studio",
            craftType: .knitting,
            sourceFileType: .pdf,
            originalAsset: nil,
            viewAsset: nil,
            originalFileName: "nordic-socks.pdf",
            pageCount: 4,
            tags: ["양말", "배색"],
            isFavorite: true,
            progress: 1,
            lastOpenedAt: Date().addingTimeInterval(-86_400 * 3),
            createdAt: Date().addingTimeInterval(-86_400 * 20),
            updatedAt: Date(),
            thumbnailStyle: .wood,
            symbol: "×",
            isSample: true
        )
    ]
}
