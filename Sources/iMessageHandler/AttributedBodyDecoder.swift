import Foundation

struct AttributedBodyDecoder {
    func decode(text: String?, attributedBody: Data?) -> DecodedText {
        if let text, !text.isEmpty {
            return DecodedText(text: text, source: "text")
        }

        guard let attributedBody, !attributedBody.isEmpty else {
            return DecodedText(text: "", source: "empty")
        }

        if let decoded = decodeAttributedArchive(attributedBody), !decoded.isEmpty {
            return DecodedText(text: decoded, source: "attributedBody")
        }

        return DecodedText(text: "", source: "undecoded")
    }

    private func decodeAttributedArchive(_ data: Data) -> String? {
        for decode in [decodeSecureObject, decodeRootObject, decodeTypedStream] {
            if let decoded = decode(data)?.trimmingCharacters(in: .whitespacesAndNewlines), !decoded.isEmpty {
                return decoded
            }
        }
        return nil
    }

    private func decodeSecureObject(_ data: Data) -> String? {
        do {
            let object = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [
                    NSAttributedString.self,
                    NSString.self,
                    NSDictionary.self,
                    NSArray.self,
                    NSData.self,
                    NSNumber.self,
                    NSURL.self
                ],
                from: data
            )
            return string(from: object)
        } catch {
            return nil
        }
    }

    private func decodeRootObject(_ data: Data) -> String? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            defer { unarchiver.finishDecoding() }

            let object = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            return string(from: object)
        } catch {
            return nil
        }
    }

    private func decodeTypedStream(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard containsASCII("streamtyped", in: bytes) else {
            return nil
        }

        if let markerDecoded = decodeTypedStreamStringMarkers(bytes) {
            return markerDecoded
        }

        var candidates: [(offset: Int, value: String)] = []
        for offset in bytes.indices.dropLast() {
            let length = Int(bytes[offset])
            guard length > 0, length <= 240, offset + 1 + length <= bytes.count else {
                continue
            }

            let slice = bytes[(offset + 1)..<(offset + 1 + length)]
            guard let value = String(bytes: slice, encoding: .utf8),
                  isPlausibleTypedStreamText(value) else {
                continue
            }
            candidates.append((offset, value))
        }

        guard let nsStringOffset = asciiRange("NSString", in: bytes)?.lowerBound else {
            return bestTypedStreamCandidate(candidates)?.value
        }

        let afterNSString = candidates.filter { candidate in
            candidate.offset > nsStringOffset
        }
        return bestTypedStreamCandidate(afterNSString)?.value ?? bestTypedStreamCandidate(candidates)?.value
    }

    private func decodeTypedStreamStringMarkers(_ bytes: [UInt8]) -> String? {
        let nsStringOffset = asciiRange("NSString", in: bytes)?.lowerBound ?? 0
        var candidates: [(offset: Int, value: String)] = []

        for offset in bytes.indices.dropLast(2) where bytes[offset] == 0x2B && offset > nsStringOffset {
            guard let encoded = typedStreamStringLength(at: offset, in: bytes) else {
                continue
            }

            let length = encoded.length
            let start = encoded.start
            let slice = bytes[start..<(start + length)]
            guard let value = String(bytes: slice, encoding: .utf8),
                  isPlausibleTypedStreamText(value) else {
                continue
            }
            candidates.append((offset, value))
        }

        return bestTypedStreamCandidate(candidates)?.value
    }

    private func typedStreamStringLength(at markerOffset: Int, in bytes: [UInt8]) -> (length: Int, start: Int)? {
        let simpleLength = Int(bytes[markerOffset + 1])
        if simpleLength > 0, simpleLength < 0x80 {
            let start = markerOffset + 2
            guard start + simpleLength <= bytes.count else {
                return nil
            }
            return (simpleLength, start)
        }

        if bytes[markerOffset + 1] == 0x81, markerOffset + 3 < bytes.count {
            let length = Int(bytes[markerOffset + 2]) | (Int(bytes[markerOffset + 3]) << 8)
            let start = markerOffset + 4
            guard length > 0, start + length <= bytes.count else {
                return nil
            }
            return (length, start)
        }

        return nil
    }

    private func string(from object: Any?) -> String? {
        if let attributed = object as? NSAttributedString {
            return attributed.string
        }
        if let string = object as? String {
            return string
        }
        if let string = object as? NSString {
            return string as String
        }
        return nil
    }

    private func isPlausibleTypedStreamText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value, !trimmed.isEmpty else {
            return false
        }

        let metadataPrefixes = ["NS", "__"]
        let metadataValues = ["streamtyped", "NSObject"]
        if metadataValues.contains(trimmed) || metadataPrefixes.contains(where: trimmed.hasPrefix) {
            return false
        }

        let scalars = trimmed.unicodeScalars
        guard scalars.allSatisfy({ scalar in
            scalar.value >= 0x20 || scalar == "\n" || scalar == "\r" || scalar == "\t"
        }) else {
            return false
        }

        return scalars.contains { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    private func bestTypedStreamCandidate(_ candidates: [(offset: Int, value: String)]) -> (offset: Int, value: String)? {
        candidates.max { left, right in
            typedStreamScore(left.value) < typedStreamScore(right.value)
        }
    }

    private func typedStreamScore(_ value: String) -> Int {
        let scalars = value.unicodeScalars
        var score = min(value.count, 80)
        if scalars.contains(where: { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) {
            score += 1_000
        }
        if value.count == 1, scalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) }) {
            score -= 100
        }
        return score
    }

    private func containsASCII(_ needle: String, in bytes: [UInt8]) -> Bool {
        asciiRange(needle, in: bytes) != nil
    }

    private func asciiRange(_ needle: String, in bytes: [UInt8]) -> Range<Int>? {
        let pattern = Array(needle.utf8)
        guard !pattern.isEmpty, pattern.count <= bytes.count else {
            return nil
        }

        for start in 0...(bytes.count - pattern.count) {
            if Array(bytes[start..<(start + pattern.count)]) == pattern {
                return start..<(start + pattern.count)
            }
        }
        return nil
    }
}

struct DecodedText {
    let text: String
    let source: String
}
