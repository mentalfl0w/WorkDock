import AppKit
import CoreGraphics
import Foundation

/// Fixtures shared by the OCR tests.
///
/// The bilingual image is committed under `Fixtures/`, so the expected text
/// lives in the repository instead of in a throwaway capture. It is a plain
/// 1040×340 white PNG with two 56pt lines — `WorkDock OCR` and
/// `福建省教育厅 收文提醒` — and must stay fixed: the assertions quote those
/// phrases. Regenerating it is fine as long as the phrases and contrast stay the
/// same. Nothing here touches the screen, the clipboard, or the user's files.
enum OCRTestImages {
    /// Committed English + Simplified Chinese image.
    ///
    /// Resolved from the test resource bundle, with the source tree as a
    /// fallback for tooling that runs the tests without one.
    static var bilingualFixtureURL: URL {
        if let bundled = Bundle.module.url(forResource: "ocr-bilingual", withExtension: "png") {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("ocr-bilingual.png", isDirectory: false)
    }

    static func bilingualFixture() throws -> Data {
        try Data(contentsOf: bilingualFixtureURL)
    }

    /// A decodable PNG with no glyphs in it. Synthetic, deterministic, and
    /// small: Vision must report "no text" instead of an image error.
    static func blankPNG(width: Int = 400, height: Int = 200) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data()
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            ?? Data()
    }
}
