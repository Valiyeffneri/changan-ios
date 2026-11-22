import Foundation
import CryptoKit

enum CommandProtocol {
    static let signatureVersion = 2
    static let defaultSharedSecret = "e54bb8b1346bc5b4ebe230482fa22a8bbf75de21d597c052466c0e981cf47873"
    static let defaultBrokerUrl = "ssl://broker.hivemq.com:8883"
    static let activeTelemetryMs: Int64 = 2500
    static let passiveTelemetryMs: Int64 = 15000
    static let telemetryOnlineStaleSeconds: Int64 = 35
    static let presenceOnlineStaleSeconds: Int64 = 60
    static let reconnectGraceSeconds: Double = 7.0
    static let pingIntervalSeconds: Double = 10.0
    static let actionPing = "PING"

    static func sign(
        action: String,
        vin: String,
        timestamp: Int64,
        msgId: String,
        params: [String: Any],
        secret: String
    ) -> String {
        let canonical = "v2\n\(action)\n\(vin)\n\(timestamp)\n\(msgId)\n\(canonicalJson(params, escapeSlash: false))"
        return hmacSha256Hex(message: canonical, secret: secret)
    }

    static func createSignedCommand(
        action: String,
        vin: String,
        params: [String: Any],
        secret: String
    ) -> (msgId: String, jsonString: String)? {
        guard !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !vin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let msgId = UUID().uuidString.lowercased()
        let timestamp = Int64(Date().timeIntervalSince1970)
        let sig = sign(action: action, vin: vin, timestamp: timestamp, msgId: msgId, params: params, secret: secret)
        let envelope: [String: Any] = [
            "signatureVersion": signatureVersion,
            "msgId": msgId,
            "vin": vin,
            "timestamp": timestamp,
            "action": action,
            "params": params,
            "signature": sig
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.withoutEscapingSlashes]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return (msgId, jsonString)
    }

    static func verifyEnvelope(_ envelope: [String: Any], secret: String) -> Bool {
        guard !secret.isEmpty else { return false }
        guard jsonInt(envelope["signatureVersion"]) == signatureVersion else { return false }
        guard let actualSig = envelope["signature"] as? String,
              actualSig.count == 64,
              actualSig.allSatisfy({ ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") }) else {
            return false
        }
        var content = envelope
        content.removeValue(forKey: "signature")

        // Support both standard org.json (unescaped '/') and Android AOSP libcore JSONObject.quote ('\/')
        let unescapedExpected = hmacSha256Hex(
            message: "event-v2\n\(canonicalJson(content, escapeSlash: false))",
            secret: secret
        )
        if constantTimeEqual(unescapedExpected, actualSig) {
            return true
        }
        let escapedExpected = hmacSha256Hex(
            message: "event-v2\n\(canonicalJson(content, escapeSlash: true))",
            secret: secret
        )
        return constantTimeEqual(escapedExpected, actualSig)
    }

    static func hmacSha256Hex(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    static func canonicalJson(_ dict: [String: Any], escapeSlash: Bool) -> String {
        canonicalValue(dict, depth: 0, escapeSlash: escapeSlash)
    }

    private static func canonicalValue(_ value: Any?, depth: Int, escapeSlash: Bool) -> String {
        guard depth <= 24 else { return "null" }
        guard let value = value else { return "null" }
        if value is NSNull { return "null" }

        if let dict = value as? [String: Any] {
            let sortedKeys = dict.keys.sorted()
            var out = "{"
            for (idx, key) in sortedKeys.enumerated() {
                if idx > 0 { out.append(",") }
                out.append(quoteJsonString(key, escapeSlash: escapeSlash))
                out.append(":")
                out.append(canonicalValue(dict[key], depth: depth + 1, escapeSlash: escapeSlash))
            }
            out.append("}")
            return out
        }

        if let array = value as? [Any] {
            var out = "["
            for (idx, item) in array.enumerated() {
                if idx > 0 { out.append(",") }
                out.append(canonicalValue(item, depth: depth + 1, escapeSlash: escapeSlash))
            }
            out.append("]")
            return out
        }

        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue ? "true" : "false"
            }
            return canonicalNumberString(num)
        }

        if let b = value as? Bool {
            return b ? "true" : "false"
        }

        if let str = value as? String {
            return quoteJsonString(str, escapeSlash: escapeSlash)
        }

        return quoteJsonString(String(describing: value), escapeSlash: escapeSlash)
    }

    private static func canonicalNumberString(_ num: NSNumber) -> String {
        let objCType = String(cString: num.objCType)
        switch objCType {
        case "c", "C", "s", "S", "i", "I", "l", "L", "q", "Q":
            return num.int64Value == 0 ? "0" : "\(num.int64Value)"
        default:
            let d = num.doubleValue
            if !d.isFinite { return "0" }
            if d == 0.0 { return "0" }
            if floor(d) == d && d >= Double(Int64.min / 2) && d <= Double(Int64.max / 2) {
                return "\(Int64(d))"
            }
            let decimal = NSDecimalNumber(decimal: num.decimalValue)
            var raw = decimal.stringValue
            if raw.contains(".") {
                while raw.hasSuffix("0") { raw.removeLast() }
                if raw.hasSuffix(".") { raw.removeLast() }
            }
            if raw == "-0" || raw.isEmpty { return "0" }
            return raw
        }
    }

    private static func quoteJsonString(_ s: String, escapeSlash: Bool) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out.append("\\\"")
            case 0x5C: out.append("\\\\")
            case 0x2F: out.append(escapeSlash ? "\\/" : "/")
            case 0x08: out.append("\\b")
            case 0x0C: out.append("\\f")
            case 0x0A: out.append("\\n")
            case 0x0D: out.append("\\r")
            case 0x09: out.append("\\t")
            case 0x00..<0x20:
                out.append(String(format: "\\u%04x", scalar.value))
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out.append("\"")
        return out
    }

    static func jsonInt(_ val: Any?) -> Int? {
        if let n = val as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            guard d.isFinite, d == floor(d) else { return nil }
            return Int(exactly: n.int64Value)
        }
        return nil
    }
}

final class WireEventVerifier {
    static let shared = WireEventVerifier()

    private let lock = NSLock()
    private let maxReplayEntries = 2048
    private let maxMediaReplayEntries = 512
    private let streamMediaTypes: Set<String> = ["CAMERA_H264", "CAMERA_FRAME", "CABIN_AUDIO_FRAME"]

    private var replayOrder: [String] = []
    private var replaySet: Set<String> = []
    private var mediaOrder: [String] = []
    private var mediaSet: Set<String> = []

    func clearReplayCache() {
        lock.lock()
        replayOrder.removeAll()
        replaySet.removeAll()
        mediaOrder.removeAll()
        mediaSet.removeAll()
        lock.unlock()
    }

    func verify(
        packet: [String: Any],
        expectedVin: String,
        secret: String,
        retainedTelemetry: Bool = false
    ) -> Bool {
        let timestamp = (packet["timestamp"] as? NSNumber)?.int64Value ?? 0
        let packetVin = (packet["vin"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let expVin = expectedVin.trimmingCharacters(in: .whitespacesAndNewlines)

        guard CommandProtocol.jsonInt(packet["signatureVersion"]) == CommandProtocol.signatureVersion else {
            return false
        }
        guard timestamp > 0 else {
            return false
        }
        guard CommandProtocol.verifyEnvelope(packet, secret: secret) else {
            return false
        }
        if !expVin.isEmpty && packetVin.caseInsensitiveCompare(expVin) != .orderedSame {
            return false
        }

        if !retainedTelemetry {
            let msgId = (packet["msgId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !msgId.isEmpty {
                let type = (packet["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let hasStatus = packet["status"] != nil && !(packet["status"] is NSNull)
                let isAck = (type == "ACK") || (hasStatus && type.isEmpty)
                let upperVin = packetVin.uppercased(with: Locale(identifier: "en_US_POSIX"))
                let isStreamMedia = !isAck && streamMediaTypes.contains(type)

                let replayKey: String
                if isAck {
                    let status = packet["status"] as? String ?? ""
                    replayKey = "ACK:\(upperVin):\(msgId):\(status)"
                } else if isStreamMedia {
                    let seq = CommandProtocol.jsonInt(packet["sequence"]) ?? -1
                    let ptsUs = (packet["ptsUs"] as? NSNumber)?.int64Value ?? timestamp
                    let cameraId = packet["cameraId"] as? String ?? ""
                    replayKey = "\(type):\(upperVin):\(msgId):\(seq):\(ptsUs):\(cameraId)"
                } else if type == "MEDIA_STATUS" {
                    let details = packet["details"] as? String ?? ""
                    replayKey = "MEDIA_STATUS:\(upperVin):\(msgId):\(timestamp):\(details)"
                } else {
                    replayKey = "\(type):\(upperVin):\(msgId)"
                }

                lock.lock()
                defer { lock.unlock() }
                if isStreamMedia {
                    if mediaSet.contains(replayKey) { return false }
                    mediaSet.insert(replayKey)
                    mediaOrder.append(replayKey)
                    if mediaOrder.count > maxMediaReplayEntries {
                        let evicted = mediaOrder.removeFirst()
                        mediaSet.remove(evicted)
                    }
                } else {
                    if replaySet.contains(replayKey) { return false }
                    replaySet.insert(replayKey)
                    replayOrder.append(replayKey)
                    if replayOrder.count > maxReplayEntries {
                        let evicted = replayOrder.removeFirst()
                        replaySet.remove(evicted)
                    }
                }
            }
        }
        return true
    }
}
