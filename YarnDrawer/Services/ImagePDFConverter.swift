import PDFKit
import UIKit

enum ImagePDFConverter {
    static func convert(imageURL: URL, outputURL: URL) throws {
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            throw PatternImportError.invalidImage
        }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            throw PatternImportError.invalidImage
        }

        let maximumSide: CGFloat = 1_440
        let scale = min(1, maximumSide / max(imageSize.width, imageSize.height))
        let pageSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let pageBounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: outputURL) { context in
            context.beginPage()
            image.draw(in: pageBounds)
        }

        guard
            let document = PDFDocument(url: outputURL),
            document.pageCount == 1
        else {
            throw PatternImportError.pdfConversionFailed
        }
    }
}

