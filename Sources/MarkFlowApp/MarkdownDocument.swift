import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    static let markdownDocument = UTType(filenameExtension: "md") ?? .plainText
}

struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [
        .markdown,
        .markdownDocument,
        .plainText,
        .utf8PlainText
    ]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            text = ""
            return
        }

        if data.isEmpty {
            text = ""
            return
        }

        if let decoded = TextDecoding.decode(data) {
            text = decoded
            return
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

enum TextDecoding {
    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), isLikelyReadableText(utf8) {
            return utf8
        }

        if looksLikeUTF16(data) {
            let utf16Candidates: [String.Encoding] = [
                .utf16LittleEndian,
                .utf16BigEndian,
                .unicode
            ]
            for encoding in utf16Candidates {
                if let value = String(data: data, encoding: encoding), isLikelyReadableText(value) {
                    return value
                }
            }
        }

        if isProbablyBinary(data) {
            return nil
        }

        var converted: NSString?
        var usedLossy = ObjCBool(false)
        let detectedEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [:],
            convertedString: &converted,
            usedLossyConversion: &usedLossy
        )
        if detectedEncoding != 0, let converted, isLikelyReadableText(converted as String) {
            return converted as String
        }

        let fallbacks: [String.Encoding] = [.windowsCP1252, .isoLatin1, .macOSRoman]
        for encoding in fallbacks {
            if let value = String(data: data, encoding: encoding), isLikelyReadableText(value) {
                return value
            }
        }

        return nil
    }

    static func isProbablyBinary(_ data: Data) -> Bool {
        if data.contains(0) {
            return true
        }

        let sampleCount = min(data.count, 4096)
        guard sampleCount > 0 else { return false }

        var suspicious = 0
        for byte in data.prefix(sampleCount) {
            switch byte {
            case 0x09, 0x0A, 0x0D:
                continue
            case 0x20...0x7E:
                continue
            case 0x80...0xFF:
                continue
            default:
                suspicious += 1
            }
        }

        return (Double(suspicious) / Double(sampleCount)) > 0.30
    }

    private static func looksLikeUTF16(_ data: Data) -> Bool {
        if data.count >= 2 {
            let bom0 = data[data.startIndex]
            let bom1 = data[data.startIndex + 1]
            if (bom0 == 0xFF && bom1 == 0xFE) || (bom0 == 0xFE && bom1 == 0xFF) {
                return true
            }
        }

        let sample = data.prefix(min(data.count, 2048))
        guard sample.count >= 8 else { return false }

        var zeroEven = 0
        var zeroOdd = 0
        var index = 0
        for byte in sample {
            if byte == 0 {
                if index % 2 == 0 {
                    zeroEven += 1
                } else {
                    zeroOdd += 1
                }
            }
            index += 1
        }

        let evenSlots = sample.count / 2
        let oddSlots = sample.count - evenSlots
        guard evenSlots > 0, oddSlots > 0 else { return false }

        let evenRatio = Double(zeroEven) / Double(evenSlots)
        let oddRatio = Double(zeroOdd) / Double(oddSlots)
        return evenRatio > 0.30 || oddRatio > 0.30
    }

    private static func isLikelyReadableText(_ value: String) -> Bool {
        if value.isEmpty { return true }

        let scalars = value.unicodeScalars
        var disallowed = 0
        for scalar in scalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:
                continue
            case 0x20...0x7E, 0x80...0x10FFFF:
                continue
            default:
                disallowed += 1
            }
        }

        let ratio = Double(disallowed) / Double(max(scalars.count, 1))
        return ratio < 0.10
    }
}
