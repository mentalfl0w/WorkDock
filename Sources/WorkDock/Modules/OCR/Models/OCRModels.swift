import Foundation

/// Where the image for one OCR run came from.
enum OCRSource: String, Codable, Sendable {
    case screen
    case clipboard
    case file

    var label: String {
        switch self {
        case .screen: return L.ocrScreenSource
        case .clipboard: return L.ocrClipboardSource
        case .file: return L.ocrFileSource
        }
    }

    var icon: String {
        switch self {
        case .screen: return "text.viewfinder"
        case .clipboard: return "doc.on.clipboard"
        case .file: return "photo"
        }
    }
}

/// Immutable output of one Vision text-recognition pass.
///
/// Pure value type so it can cross actor boundaries under Swift 6 concurrency.
struct OCRRecognition: Sendable, Equatable {
    let text: String
    let lineCount: Int
    let averageConfidence: Double
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
}
