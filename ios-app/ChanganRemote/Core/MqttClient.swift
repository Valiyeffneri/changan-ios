import Foundation
import Network
import Security

enum CloudTransportState: String {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case reconnecting = "RECONNECTING"
    case connected = "CONNECTED"
}

/// Pure-Swift MQTT v3.1.1 transport over Apple Network.framework (TLS & TCP).
final class MqttClient {
    private struct OutgoingItem {
        let id: String
        let topic: String
        let payload: Data
        let qos: Int
        let queuedAt: Date
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "az.c589.changanremote.mqtt", qos: .userInitiated)

    private var brokerUrl: String
    private var vin: String
    private var secretKey: String
    var allowInsecureCustomTls: Bool = false

    private var connection: NWConnection?
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var requested = false
    private var generation: UInt64 = 0
    private var hasConnectedOnce = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var pingTimer: DispatchSourceTimer?
    private var packetIdCounter: UInt16 = 1

    private var rxBuffer = Data()
    private var outbox: [OutgoingItem] = []
    private var isSending = false
    private var handshakeComplete = false
    private var backoffSeconds: Double = 1.0

    private let maxPayloadBytes = 2 * 1024 * 1024
    private let maxQueueAgeSeconds: TimeInterval = 15.0
    private let minBackoff: Double = 1.0
    private let maxBackoff: Double = 15.0

    private lazy var stableClientId: String = {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "changan_mqtt_client_suffix"), !saved.isEmpty {
            return "ChanganPhoneIOS_\(saved)"
        }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        defaults.set(String(suffix), forKey: "changan_mqtt_client_suffix")
        return "ChanganPhoneIOS_\(suffix)"
    }()

    var onStateChanged: ((CloudTransportState) -> Void)?
    var onTelemetryReceived: ((TelemetryState) -> Void)?
    var onAckReceived: (([String: Any]) -> Void)?
    var onMediaReceived: (([String: Any]) -> Void)?
    var onPresenceChanged: ((Bool, Int64) -> Void)?
    var onTransportStatus: ((String, String, String) -> Void)?

    private(set) var state: CloudTransportState = .disconnected {
        didSet {
            if state != oldValue {
                let s = state
                DispatchQueue.main.async { [weak self] in
                    self?.onStateChanged?(s)
                }
            }
        }
    }

    init(brokerUrl: String, vin: String, secretKey: String) {
        self.brokerUrl = brokerUrl
        self.vin = vin
        self.secretKey = secretKey
    }

    func updateConfig(brokerUrl: String, vin: String, secretKey: String) {
        lock.lock()
        let wasRequested = requested
        lock.unlock()

        disconnect()

        lock.lock()
        self.brokerUrl = brokerUrl
        self.vin = vin
        self.secretKey = secretKey
        lock.unlock()

        if wasRequested {
            connect()
        }
    }

    func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.requested = true
            let currentVin = self.vin.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentBroker = self.brokerUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let alreadyActive = self.connection != nil
            self.lock.unlock()

            guard !currentVin.isEmpty else {
                self.state = .disconnected
                return
            }
            self.startPathMonitorIfNeeded()
            if alreadyActive { return }
            self.startConnectionAttempt(broker: currentBroker, vin: currentVin)
        }
    }

    func reconnectNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldConnect = self.requested && !self.vin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            self.lock.unlock()
            guard shouldConnect else { return }
            self.teardownConnectionOnly(notifyDisconnected: false)
            self.backoffSeconds = self.minBackoff
            self.lock.lock()
            let broker = self.brokerUrl
            let vehicleVin = self.vin
            self.lock.unlock()
            self.startConnectionAttempt(broker: broker, vin: vehicleVin)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.requested = false
            self.generation &+= 1
            let expired = self.outbox
            self.outbox.removeAll()
            self.lock.unlock()

            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.stopPathMonitor()
            self.teardownConnectionOnly(notifyDisconnected: true)

            for item in expired where !item.id.isEmpty && !item.id.hasPrefix("audio-") {
                self.onTransportStatus?(item.id, "CANCELLED", "Əmr göndərilməsi dayandırıldı")
            }
        }
    }

    @discardableResult
    func sendSignedCommand(_ jsonString: String, msgId: String) -> Bool {
        enqueueOutgoing(id: msgId, jsonString: jsonString, qos: 1, dropIfFull: false)
    }

    @discardableResult
    func sendLiveAudio(_ jsonString: String) -> Bool {
        enqueueOutgoing(id: "audio-\(UUID().uuidString)", jsonString: jsonString, qos: 0, dropIfFull: true)
    }

    private func enqueueOutgoing(id: String, jsonString: String, qos: Int, dropIfFull: Bool) -> Bool {
        lock.lock()
        guard requested else {
            lock.unlock()
            return false
        }
        let currentVin = vin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentVin.isEmpty, let data = jsonString.data(using: .utf8) else {
            lock.unlock()
            return false
        }
        if outbox.count >= 32 {
            if dropIfFull {
                outbox.removeFirst()
            } else {
                lock.unlock()
                return false
            }
        }
        let topic = "changan/c589/\(currentVin)/command"
        outbox.append(OutgoingItem(id: id, topic: topic, payload: data, qos: qos, queuedAt: Date()))
        lock.unlock()

        queue.async { [weak self] in
            self?.drainOutbox()
        }
        return true
    }

    private func startPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.queue.async {
                let prev = self.lastPathStatus
                self.lastPathStatus = path.status
                if path.status == .satisfied && prev != .satisfied && self.state != .connected {
                    self.backoffSeconds = self.minBackoff
                    self.reconnectNow()
                }
            }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        lastPathStatus = nil
    }

    private func parseBroker(_ raw: String) -> (host: String, port: UInt16, useTls: Bool)? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        let scheme = (url.scheme ?? "ssl").lowercased()
        let useTls = (scheme == "ssl" || scheme == "tls" || scheme == "wss")
        let defaultPort: UInt16 = useTls ? 8883 : 1883
        let port = url.port.flatMap { UInt16(exactly: $0) } ?? defaultPort
        return (host, port, useTls)
    }

    private func startConnectionAttempt(broker: String, vin: String) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        guard let parsed = parseBroker(broker),
              let nwPort = NWEndpoint.Port(rawValue: parsed.port) else {
            scheduleReconnect(vin: vin)
            return
        }

        lock.lock()
        generation &+= 1
        let myGen = generation
        let insecure = allowInsecureCustomTls
        lock.unlock()

        rxBuffer.removeAll(keepingCapacity: true)
        handshakeComplete = false
        isSending = false
        state = hasConnectedOnce ? .reconnecting : .connecting

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 10
        tcpOptions.noDelay = true

        let params: NWParameters
        if parsed.useTls {
            let tlsOptions = NWProtocolTLS.Options()
            if insecure {
                sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, completion in
                    completion(true)
                }, queue)
            }
            params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            params = NWParameters(tls: nil, tcp: tcpOptions)
        }

        let conn = NWConnection(host: NWEndpoint.Host(parsed.host), port: nwPort, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            guard self.isCurrentGeneration(myGen) else { return }
            switch newState {
            case .ready:
                self.sendConnectPacket(on: conn, generation: myGen)
                self.receiveLoop(on: conn, generation: myGen, vin: vin)
            case .failed:
                self.handleConnectionFailure(vin: vin, generation: myGen)
            case .cancelled:
                break
            case .waiting:
                self.state = self.hasConnectedOnce ? .reconnecting : .connecting
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func isCurrentGeneration(_ gen: UInt64) -> Bool {
        lock.lock()
        let ok = requested && generation == gen
        lock.unlock()
        return ok
    }

    private func teardownConnectionOnly(notifyDisconnected: Bool) {
        stopPingTimer()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        handshakeComplete = false
        isSending = false
        rxBuffer.removeAll(keepingCapacity: false)
        if notifyDisconnected {
            state = .disconnected
        }
    }

    private func handleConnectionFailure(vin: String, generation myGen: UInt64) {
        guard isCurrentGeneration(myGen) else { return }
        teardownConnectionOnly(notifyDisconnected: false)
        state = hasConnectedOnce ? .reconnecting : .connecting
        scheduleReconnect(vin: vin)
    }

    private func scheduleReconnect(vin: String) {
        lock.lock()
        let active = requested
        let myGen = generation
        let broker = brokerUrl
        lock.unlock()
        guard active, !vin.isEmpty else { return }

        reconnectWorkItem?.cancel()
        let delay = backoffSeconds
        backoffSeconds = min(maxBackoff, backoffSeconds * 2.0)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isCurrentGeneration(myGen) else { return }
            self.startConnectionAttempt(broker: broker, vin: vin)
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - MQTT Wire Encoding / Decoding

    private func nextPacketId() -> UInt16 {
        packetIdCounter = packetIdCounter == UInt16.max ? 1 : packetIdCounter + 1
        return packetIdCounter
    }

    private func encodeUtf8(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        var data = Data()
        let len = UInt16(clamping: bytes.count)
        data.append(UInt8((len >> 8) & 0xFF))
        data.append(UInt8(len & 0xFF))
        data.append(bytes)
        return data
    }

    private func encodeRemainingLength(_ length: Int) -> Data {
        var x = length
        var out = Data()
        repeat {
            var byte = UInt8(x & 0x7F)
            x >>= 7
            if x > 0 { byte |= 0x80 }
            out.append(byte)
        } while x > 0
        return out
    }

    private func buildPacket(headerByte: UInt8, body: Data) -> Data {
        var pkt = Data([headerByte])
        pkt.append(encodeRemainingLength(body.count))
        pkt.append(body)
        return pkt
    }

    private func sendConnectPacket(on conn: NWConnection, generation myGen: UInt64) {
        var body = Data()
        body.append(encodeUtf8("MQTT"))
        body.append(0x04) // MQTT 3.1.1
        body.append(0x02) // Clean Session
        body.append(0x00)
        body.append(20)   // KeepAlive = 20s
        body.append(encodeUtf8(stableClientId))

        let packet = buildPacket(headerByte: 0x10, body: body)
        conn.send(content: packet, completion: .contentProcessed({ [weak self] err in
            if err != nil {
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.handleConnectionFailure(vin: self.vin, generation: myGen)
                }
            }
        }))
    }

    private func sendSubscribePacket(on conn: NWConnection, vin: String, generation myGen: UInt64) {
        let prefix = "changan/c589/\(vin)"
        let topics: [(String, UInt8)] = [
            ("\(prefix)/telemetry", 0),
            ("\(prefix)/ack", 1),
            ("\(prefix)/media", 0),
            ("\(prefix)/presence", 1)
        ]
        var body = Data()
        let pid = nextPacketId()
        body.append(UInt8((pid >> 8) & 0xFF))
        body.append(UInt8(pid & 0xFF))
        for (topic, qos) in topics {
            body.append(encodeUtf8(topic))
            body.append(qos)
        }
        let packet = buildPacket(headerByte: 0x82, body: body)
        conn.send(content: packet, completion: .contentProcessed({ [weak self] err in
            guard let self else { return }
            self.queue.async {
                guard self.isCurrentGeneration(myGen) else { return }
                if err != nil {
                    self.handleConnectionFailure(vin: vin, generation: myGen)
                    return
                }
                self.hasConnectedOnce = true
                self.backoffSeconds = self.minBackoff
                self.handshakeComplete = true
                self.state = .connected
                self.startPingTimer(on: conn, generation: myGen, vin: vin)
                self.drainOutbox()
            }
        }))
    }

    private func startPingTimer(on conn: NWConnection, generation myGen: UInt64, vin: String) {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 12.0, repeating: 12.0)
        timer.setEventHandler { [weak self] in
            guard let self, self.isCurrentGeneration(myGen), self.handshakeComplete else { return }
            let pingReq = Data([0xC0, 0x00])
            conn.send(content: pingReq, completion: .contentProcessed({ err in
                if err != nil {
                    self.queue.async {
                        self.handleConnectionFailure(vin: vin, generation: myGen)
                    }
                }
            }))
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func receiveLoop(on conn: NWConnection, generation myGen: UInt64, vin: String) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard self.isCurrentGeneration(myGen), self.connection === conn else { return }
            if let data, !data.isEmpty {
                self.rxBuffer.append(data)
                self.parseAvailablePackets(on: conn, generation: myGen, vin: vin)
            }
            if error != nil || isComplete {
                self.handleConnectionFailure(vin: vin, generation: myGen)
                return
            }
            self.receiveLoop(on: conn, generation: myGen, vin: vin)
        }
    }

    private func parseAvailablePackets(on conn: NWConnection, generation myGen: UInt64, vin: String) {
        while rxBuffer.count >= 2 {
            let firstByte = rxBuffer[rxBuffer.startIndex]
            var multiplier = 1
            var remainingLength = 0
            var lenBytes = 0
            var malformed = false
            var incomplete = false

            while true {
                let idx = rxBuffer.startIndex + 1 + lenBytes
                if idx >= rxBuffer.endIndex {
                    incomplete = true
                    break
                }
                let encoded = Int(rxBuffer[idx])
                remainingLength += (encoded & 0x7F) * multiplier
                lenBytes += 1
                if (encoded & 0x80) == 0 {
                    break
                }
                multiplier *= 128
                if lenBytes >= 4 {
                    malformed = true
                    break
                }
            }

            if malformed {
                handleConnectionFailure(vin: vin, generation: myGen)
                return
            }
            if incomplete { return }

            let totalLength = 1 + lenBytes + remainingLength
            guard rxBuffer.count >= totalLength else { return }

            let bodyStart = rxBuffer.startIndex + 1 + lenBytes
            let bodyEnd = rxBuffer.startIndex + totalLength
            let body = rxBuffer.subdata(in: bodyStart..<bodyEnd)
            rxBuffer.removeFirst(totalLength)

            let packetType = firstByte >> 4
            let flags = firstByte & 0x0F

            switch packetType {
            case 2: // CONNACK
                guard body.count >= 2, body[body.startIndex + 1] == 0 else {
                    handleConnectionFailure(vin: vin, generation: myGen)
                    return
                }
                sendSubscribePacket(on: conn, vin: vin, generation: myGen)

            case 3: // PUBLISH
                handlePublishPacket(flags: flags, body: body, on: conn, vin: vin)

            case 9: // SUBACK
                break
            case 13: // PINGRESP
                break
            case 4: // PUBACK
                break
            default:
                break
            }
        }
    }

    private func handlePublishPacket(flags: UInt8, body: Data, on conn: NWConnection, vin: String) {
        guard body.count >= 2 else { return }
        let topicLen = (Int(body[body.startIndex]) << 8) | Int(body[body.startIndex + 1])
        var offset = body.startIndex + 2
        guard offset + topicLen <= body.endIndex else { return }
        let topicData = body.subdata(in: offset..<(offset + topicLen))
        let topic = String(data: topicData, encoding: .utf8) ?? ""
        offset += topicLen

        let qos = (flags >> 1) & 0x03
        let retained = (flags & 0x01) != 0

        if qos > 0 {
            guard offset + 2 <= body.endIndex else { return }
            let pidHigh = body[offset]
            let pidLow = body[offset + 1]
            offset += 2
            if qos == 1 {
                let puback = Data([0x40, 0x02, pidHigh, pidLow])
                conn.send(content: puback, completion: .contentProcessed({ _ in }))
            }
        }

        let payload = body.subdata(in: offset..<body.endIndex)
        guard payload.count <= maxPayloadBytes else { return }
        guard let json = (try? JSONSerialization.jsonObject(with: payload, options: [])) as? [String: Any] else {
            return
        }

        lock.lock()
        let activeSecret = secretKey
        lock.unlock()

        let prefix = "changan/c589/\(vin)"
        let retainedTelemetry = (topic == "\(prefix)/telemetry") && retained
        guard WireEventVerifier.shared.verify(
            packet: json,
            expectedVin: vin,
            secret: activeSecret,
            retainedTelemetry: retainedTelemetry
        ) else {
            return
        }

        if topic == "\(prefix)/telemetry" {
            let live = !retained
            if live {
                let nowSec = Int64(Date().timeIntervalSince1970)
                onPresenceChanged?(true, nowSec)
            }
            var parsed = TelemetryParser.parse(json, expectedVin: vin)
            parsed.isLiveCloudSample = live
            onTelemetryReceived?(parsed)
        } else if topic == "\(prefix)/presence" {
            let online = (json["online"] as? Bool) ?? ((json["online"] as? NSNumber)?.boolValue ?? false)
            let ts = (json["timestamp"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970)
            onPresenceChanged?(online, ts)
        } else if topic == "\(prefix)/ack" {
            onAckReceived?(json)
        } else if topic == "\(prefix)/media" {
            onMediaReceived?(json)
        }
    }

    private func drainOutbox() {
        guard handshakeComplete, let conn = connection, !isSending else { return }

        lock.lock()
        if outbox.isEmpty {
            lock.unlock()
            return
        }
        let next = outbox.removeFirst()
        lock.unlock()

        if Date().timeIntervalSince(next.queuedAt) > maxQueueAgeSeconds {
            if !next.id.isEmpty && !next.id.hasPrefix("audio-") {
                onTransportStatus?(next.id, "EXPIRED", "Əmr qoşulmanı gözləyərkən vaxtı bitdi")
            }
            drainOutbox()
            return
        }

        isSending = true
        var body = encodeUtf8(next.topic)
        if next.qos > 0 {
            let pid = nextPacketId()
            body.append(UInt8((pid >> 8) & 0xFF))
            body.append(UInt8(pid & 0xFF))
        }
        body.append(next.payload)
        let header: UInt8 = next.qos == 1 ? 0x32 : 0x30
        let pkt = buildPacket(headerByte: header, body: body)

        lock.lock()
        let currentGen = generation
        let currentVin = vin
        lock.unlock()

        conn.send(content: pkt, completion: .contentProcessed({ [weak self] err in
            guard let self else { return }
            self.queue.async {
                self.isSending = false
                if err != nil {
                    if !next.id.isEmpty && !next.id.hasPrefix("audio-") {
                        self.onTransportStatus?(next.id, "FAILED", "Göndərmə nəticəsi məlum deyil")
                    }
                    self.handleConnectionFailure(vin: currentVin, generation: currentGen)
                } else {
                    if !next.id.isEmpty && !next.id.hasPrefix("audio-") {
                        self.onTransportStatus?(next.id, "SENT", "Buluda göndərildi; təsdiq gözlənilir")
                    }
                    self.drainOutbox()
                }
            }
        }))
    }
}
