import CryptoKit
import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

enum PatternImportError: LocalizedError {
    case unsupportedFileType
    case inaccessibleFile
    case invalidImage
    case invalidPDF
    case pdfConversionFailed
    case storageFailure

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            "PDF, JPG, JPEG, PNG 파일만 등록할 수 있습니다."
        case .inaccessibleFile:
            "선택한 파일에 접근할 수 없습니다. 파일을 다시 선택해 주세요."
        case .invalidImage:
            "이미지를 읽을 수 없습니다. 다른 파일을 선택해 주세요."
        case .invalidPDF:
            "PDF를 읽을 수 없거나 암호화되어 있습니다."
        case .pdfConversionFailed:
            "작업용 PDF 변환에 실패했습니다. 다시 시도해 주세요."
        case .storageFailure:
            "파일을 저장하지 못했습니다. 저장 공간을 확인해 주세요."
        }
    }
}

actor FileAssetStore {
    private let fileManager: FileManager
    private let appRootURL: URL
    private let patternsRootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            appRootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            appRootURL = applicationSupport.appending(
                path: "YarnDrawer",
                directoryHint: .isDirectory
            )
        }
        patternsRootURL = appRootURL.appending(path: "patterns", directoryHint: .isDirectory)
    }

    func importPattern(_ draft: PatternImportDraft) throws -> PatternItem {
        let sourceURL = draft.sourceURL
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw PatternImportError.inaccessibleFile
        }

        let sourceFileType = try resolveFileType(sourceURL)
        let patternID = UUID()
        let patternDirectory = patternsRootURL.appending(
            path: patternID.uuidString,
            directoryHint: .isDirectory
        )
        let originalDirectory = patternDirectory.appending(
            path: "original",
            directoryHint: .isDirectory
        )
        let viewDirectory = patternDirectory.appending(
            path: "view",
            directoryHint: .isDirectory
        )
        let thumbnailDirectory = patternDirectory.appending(
            path: "thumbnail",
            directoryHint: .isDirectory
        )

        do {
            try fileManager.createDirectory(
                at: originalDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: viewDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: thumbnailDirectory,
                withIntermediateDirectories: true
            )

            let originalURL = originalDirectory.appending(
                path: sanitizedFileName(sourceURL.lastPathComponent)
            )
            try fileManager.copyItem(at: sourceURL, to: originalURL)

            let originalAsset = try makeAsset(
                purpose: .original,
                url: originalURL,
                root: patternDirectory,
                mimeType: sourceFileType.mimeType,
                derivedFromAssetID: nil
            )

            let viewAsset: FileAsset
            let pageCount: Int

            if sourceFileType == .pdf {
                guard let document = PDFDocument(url: originalURL), document.pageCount > 0 else {
                    throw PatternImportError.invalidPDF
                }
                viewAsset = originalAsset
                pageCount = document.pageCount
            } else {
                let viewURL = viewDirectory.appending(path: "document.pdf")
                try ImagePDFConverter.convert(imageURL: originalURL, outputURL: viewURL)
                guard let document = PDFDocument(url: viewURL) else {
                    throw PatternImportError.pdfConversionFailed
                }
                viewAsset = try makeAsset(
                    purpose: .viewPDF,
                    url: viewURL,
                    root: patternDirectory,
                    mimeType: UTType.pdf.preferredMIMEType ?? "application/pdf",
                    derivedFromAssetID: originalAsset.id
                )
                pageCount = document.pageCount
            }

            try makeThumbnail(
                sourceURL: sourceFileType == .pdf ? originalURL : viewDirectory.appending(path: "document.pdf"),
                outputURL: thumbnailDirectory.appending(path: "card.png")
            )

            let now = Date()
            return PatternItem(
                id: patternID,
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                designerName: draft.designerName.nilIfBlank,
                craftType: draft.craftType,
                sourceFileType: sourceFileType,
                originalAsset: originalAsset,
                viewAsset: viewAsset,
                originalFileName: sourceURL.lastPathComponent,
                pageCount: pageCount,
                tags: draft.tags,
                isFavorite: false,
                progress: 0,
                lastOpenedAt: nil,
                createdAt: now,
                updatedAt: now,
                thumbnailStyle: draft.craftType == .knitting ? .green : .cream,
                symbol: draft.craftType == .knitting ? "V" : "○",
                isSample: false
            )
        } catch {
            try? fileManager.removeItem(at: patternDirectory)
            if let importError = error as? PatternImportError {
                throw importError
            }
            throw PatternImportError.storageFailure
        }
    }

    func fileURL(for asset: FileAsset, patternID: UUID) -> URL {
        patternsRootURL
            .appending(path: patternID.uuidString, directoryHint: .isDirectory)
            .appending(path: asset.storageKey)
    }

    func thumbnailURL(for pattern: PatternItem) -> URL? {
        guard !pattern.isSample else {
            return nil
        }
        let url = thumbnailURL(patternID: pattern.id)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func deletePatternFiles(patternID: UUID) throws {
        let patternDirectory = patternsRootURL.appending(
            path: patternID.uuidString,
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: patternDirectory.path) else {
            return
        }
        try fileManager.removeItem(at: patternDirectory)
    }

    func reconnectPatternFile(
        sourceURL: URL,
        for pattern: PatternItem
    ) throws -> PatternItem {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw PatternImportError.inaccessibleFile
        }

        let sourceFileType = try resolveFileType(sourceURL)
        let patternDirectory = patternsRootURL.appending(
            path: pattern.id.uuidString,
            directoryHint: .isDirectory
        )
        let tempDirectory = patternDirectory.appending(
            path: "reconnect-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let tempOriginalDirectory = tempDirectory.appending(
            path: "original",
            directoryHint: .isDirectory
        )
        let tempViewDirectory = tempDirectory.appending(
            path: "view",
            directoryHint: .isDirectory
        )
        let tempThumbnailDirectory = tempDirectory.appending(
            path: "thumbnail",
            directoryHint: .isDirectory
        )

        do {
            try fileManager.createDirectory(
                at: tempOriginalDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: tempViewDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: tempThumbnailDirectory,
                withIntermediateDirectories: true
            )

            let fileName = sanitizedFileName(sourceURL.lastPathComponent)
            let tempOriginalURL = tempOriginalDirectory.appending(path: fileName)
            try fileManager.copyItem(at: sourceURL, to: tempOriginalURL)

            let pageCount: Int
            if sourceFileType == .pdf {
                guard let document = PDFDocument(url: tempOriginalURL), document.pageCount > 0 else {
                    throw PatternImportError.invalidPDF
                }
                pageCount = document.pageCount
            } else {
                let tempViewURL = tempViewDirectory.appending(path: "document.pdf")
                try ImagePDFConverter.convert(imageURL: tempOriginalURL, outputURL: tempViewURL)
                guard let document = PDFDocument(url: tempViewURL), document.pageCount == 1 else {
                    throw PatternImportError.pdfConversionFailed
                }
                pageCount = document.pageCount
            }

            try makeThumbnail(
                sourceURL: sourceFileType == .pdf ? tempOriginalURL : tempViewDirectory.appending(path: "document.pdf"),
                outputURL: tempThumbnailDirectory.appending(path: "card.png")
            )

            try fileManager.createDirectory(
                at: patternDirectory,
                withIntermediateDirectories: true
            )
            let finalOriginalDirectory = patternDirectory.appending(
                path: "original",
                directoryHint: .isDirectory
            )
            let finalViewDirectory = patternDirectory.appending(
                path: "view",
                directoryHint: .isDirectory
            )
            let finalThumbnailDirectory = patternDirectory.appending(
                path: "thumbnail",
                directoryHint: .isDirectory
            )
            try? fileManager.removeItem(at: finalOriginalDirectory)
            try? fileManager.removeItem(at: finalViewDirectory)
            try? fileManager.removeItem(at: finalThumbnailDirectory)
            try fileManager.moveItem(at: tempOriginalDirectory, to: finalOriginalDirectory)
            try fileManager.moveItem(at: tempViewDirectory, to: finalViewDirectory)
            try fileManager.moveItem(at: tempThumbnailDirectory, to: finalThumbnailDirectory)
            try? fileManager.removeItem(at: tempDirectory)

            let finalOriginalURL = finalOriginalDirectory.appending(path: fileName)
            let originalAsset = try makeAsset(
                purpose: .original,
                url: finalOriginalURL,
                root: patternDirectory,
                mimeType: sourceFileType.mimeType,
                derivedFromAssetID: nil
            )
            let viewAsset: FileAsset
            if sourceFileType == .pdf {
                viewAsset = originalAsset
            } else {
                viewAsset = try makeAsset(
                    purpose: .viewPDF,
                    url: finalViewDirectory.appending(path: "document.pdf"),
                    root: patternDirectory,
                    mimeType: UTType.pdf.preferredMIMEType ?? "application/pdf",
                    derivedFromAssetID: originalAsset.id
                )
            }

            var updatedPattern = pattern
            updatedPattern.sourceFileType = sourceFileType
            updatedPattern.originalAsset = originalAsset
            updatedPattern.viewAsset = viewAsset
            updatedPattern.originalFileName = sourceURL.lastPathComponent
            updatedPattern.pageCount = pageCount
            updatedPattern.updatedAt = Date()
            return updatedPattern
        } catch {
            try? fileManager.removeItem(at: tempDirectory)
            if let importError = error as? PatternImportError {
                throw importError
            }
            throw PatternImportError.storageFailure
        }
    }

    func appDataByteSize() -> Int64 {
        guard fileManager.fileExists(atPath: appRootURL.path) else {
            return 0
        }
        guard let enumerator = fileManager.enumerator(
            at: appRootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                ),
                values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    func deleteAllAppData() throws {
        guard fileManager.fileExists(atPath: appRootURL.path) else {
            return
        }
        try fileManager.removeItem(at: appRootURL)
    }

    func missingFilePatternIDs(for patterns: [PatternItem]) -> Set<PatternItem.ID> {
        Set(
            patterns.compactMap { pattern in
                guard !pattern.isSample else {
                    return nil
                }
                let assets = [pattern.originalAsset, pattern.viewAsset].compactMap(\.self)
                guard !assets.isEmpty else {
                    return pattern.id
                }
                let hasMissingFile = assets.contains {
                    !fileManager.fileExists(
                        atPath: fileURL(for: $0, patternID: pattern.id).path
                    )
                }
                return hasMissingFile ? pattern.id : nil
            }
        )
    }

    func checksumMismatchPatternIDs(for patterns: [PatternItem]) -> Set<PatternItem.ID> {
        Set(
            patterns.compactMap { pattern in
                guard !pattern.isSample else {
                    return nil
                }
                let assets = [pattern.originalAsset, pattern.viewAsset].compactMap(\.self)
                guard !assets.isEmpty else {
                    return nil
                }
                let hasMismatch = assets.contains { asset in
                    let url = fileURL(for: asset, patternID: pattern.id)
                    guard fileManager.fileExists(atPath: url.path) else {
                        return false
                    }
                    return (try? checksum(url)) != asset.checksumSHA256
                }
                return hasMismatch ? pattern.id : nil
            }
        )
    }

    private func resolveFileType(_ url: URL) throws -> SourceFileType {
        switch url.pathExtension.localizedLowercase {
        case "pdf": .pdf
        case "jpg": .jpg
        case "jpeg": .jpeg
        case "png": .png
        default: throw PatternImportError.unsupportedFileType
        }
    }

    private func makeAsset(
        purpose: FileAssetPurpose,
        url: URL,
        root: URL,
        mimeType: String,
        derivedFromAssetID: UUID?
    ) throws -> FileAsset {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? NSNumber
        return FileAsset(
            id: UUID(),
            purpose: purpose,
            storageKey: url.path.replacingOccurrences(of: root.path + "/", with: ""),
            mimeType: mimeType,
            byteSize: size?.int64Value ?? 0,
            checksumSHA256: try checksum(url),
            derivedFromAssetID: derivedFromAssetID,
            createdAt: Date()
        )
    }

    private func thumbnailURL(patternID: UUID) -> URL {
        patternsRootURL
            .appending(path: patternID.uuidString, directoryHint: .isDirectory)
            .appending(path: "thumbnail", directoryHint: .isDirectory)
            .appending(path: "card.png")
    }

    private func makeThumbnail(sourceURL: URL, outputURL: URL) throws {
        let thumbnailSize = CGSize(width: 360, height: 480)
        let image: UIImage?
        if sourceURL.pathExtension.localizedLowercase == "pdf" {
            image = PDFDocument(url: sourceURL)?
                .page(at: 0)?
                .thumbnail(of: thumbnailSize, for: .cropBox)
        } else {
            image = UIImage(contentsOfFile: sourceURL.path)
        }
        guard let image else {
            throw PatternImportError.storageFailure
        }

        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let renderedImage = renderer.image { context in
            UIColor(red: 1, green: 253 / 255, blue: 247 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: thumbnailSize))

            let scale = min(
                thumbnailSize.width / max(image.size.width, 1),
                thumbnailSize.height / max(image.size.height, 1)
            )
            let drawSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let drawRect = CGRect(
                x: (thumbnailSize.width - drawSize.width) / 2,
                y: (thumbnailSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
        }
        guard let data = renderedImage.pngData() else {
            throw PatternImportError.storageFailure
        }
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }

    private func checksum(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(sanitized)
    }
}

private extension SourceFileType {
    var mimeType: String {
        switch self {
        case .pdf: "application/pdf"
        case .jpg, .jpeg: "image/jpeg"
        case .png: "image/png"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
