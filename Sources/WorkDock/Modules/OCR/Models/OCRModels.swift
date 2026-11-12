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

/// Optional cleanup applied to a newly recognized result before it becomes
/// editable text.
///
/// This is a pure value type on purpose: the rules are the store's contract
/// with the page and with the tests, and they run exactly once per result. A
/// change to the options therefore cannot rewrite text that is already on
/// screen, and the raw recognition output stays intact for the statistics.
struct OCRTextCleanup: Equatable, Sendable {
    /// Drop `\r` and `\n`, including both characters of a CRLF pair.
    var stripLineBreaks: Bool

    /// Drop an ordinary space and the ideographic space U+3000. Tabs are kept,
    /// and line breaks stay unless ``stripLineBreaks`` removes them.
    var stripSpaces: Bool

    /// Both options off: the raw recognition result.
    static let none = OCRTextCleanup(stripLineBreaks: false, stripSpaces: false)

    /// The text one recognition result contributes to the editable field.
    func apply(to text: String) -> String {
        guard stripLineBreaks || stripSpaces else { return text }

        var result = String()
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if stripLineBreaks && (value == 0x0A || value == 0x0D) { continue }
            if stripSpaces && (value == 0x20 || value == 0x3000) { continue }
            result.unicodeScalars.append(scalar)
        }
        return result
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
