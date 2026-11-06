import CryptoKit
import Foundation

/// The caller's continuation note is opaque provider input. Validation never normalizes its body.
enum AgentSessionSelfCompactNotePolicy {
    static let maximumUTF8Bytes = 8192
    static let maximumIdempotencyKeyUTF8Bytes = 200
    private static let digestDomain = "agent_self.compact/v1\n"

    enum Validation: Equatable {
        case valid(byteCount: Int)
        case empty
        case tooLong(byteCount: Int, maximum: Int)
        case invalidScalar
    }

    static func validation(of note: String) -> Validation {
        let byteCount = note.utf8.count
        guard byteCount <= maximumUTF8Bytes else {
            return .tooLong(byteCount: byteCount, maximum: maximumUTF8Bytes)
        }
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard !containsDisallowedControl(in: note) else {
            return .invalidScalar
        }
        return .valid(byteCount: byteCount)
    }

    static func idempotencyKeyIsValid(_ key: String) -> Bool {
        !key.isEmpty
            && key.utf8.count <= maximumIdempotencyKeyUTF8Bytes
            && !containsDisallowedControl(in: key)
    }

    static func digest(of note: String) -> String {
        let hash = SHA256.hash(data: Data((digestDomain + note).utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func containsDisallowedControl(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            if value == 0x09 || value == 0x0A || value == 0x0D {
                return false
            }
            return value <= 0x1F || (0x7F ... 0x9F).contains(value)
        }
    }
}
