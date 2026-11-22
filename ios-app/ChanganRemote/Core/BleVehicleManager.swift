import Foundation
import CoreBluetooth

enum BtConnectionState: String {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
}

/// CoreBluetooth BLE Central client communicating directly with BleGattAgentServer on the vehicle head unit.
final class BleVehicleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let serviceUuid = CBUUID(string: "5ea7c589-2677-4e6b-9a13-1b5c9d28f701")
    private static let commandRxUuid = CBUUID(string: "5ea7c589-2677-4e6b-9a13-1b5c9d28f702")
    private static let telemetryTxUuid = CBUUID(string: "5ea7c589-2677-4e6b-9a13-1b5c9d28f703")

    private let queue = DispatchQueue(label: "az.c589.changanremote.ble", qos: .userInitiated)
    private let lock = NSLock()

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    private var requested = false
    private var expectedVin: String
    private var secretKey: String
    private var rxBuffer = Data()
    private var rescanTimer: DispatchSourceTimer?

    var onStateChanged: ((BtConnectionState) -> Void)?
    var onTelemetryReceived: ((TelemetryState) -> Void)?
    var onAckReceived: (([String: Any]) -> Void)?
    var onMediaReceived: (([String: Any]) -> Void)?
    var onHeartbeatReceived: ((Int64) -> Void)?
    var onVinSynced: ((String) -> Void)?

    private(set) var state: BtConnectionState = .disconnected {
        didSet {
            if state != oldValue {
                let s = state
                DispatchQueue.main.async { [weak self] in
                    self?.onStateChanged?(s)
                }
            }
        }
    }

    init(expectedVin: String, secretKey: String) {
        self.expectedVin = expectedVin
        self.secretKey = secretKey
        super.init()
    }

    func updateCredentials(vin: String, secret: String) {
        lock.lock()
        self.expectedVin = vin
        self.secretKey = secret
        lock.unlock()
    }

    func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.requested = true
            self.lock.unlock()

            if self.centralManager == nil {
                self.state = .connecting
                self.centralManager = CBCentralManager(delegate: self, queue: self.queue)
            } else {
                self.beginScanOrConnectIfReady()
            }
            self.startRescanWatchdog()
        }
    }

    func reconnectNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let active = self.requested
            self.lock.unlock()
            guard active else { return }
            self.beginScanOrConnectIfReady()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.requested = false
            self.lock.unlock()

            self.stopRescanWatchdog()
            self.centralManager?.stopScan()
            if let p = self.connectedPeripheral {
                self.centralManager?.cancelPeripheralConnection(p)
            }
            self.connectedPeripheral = nil
            self.rxCharacteristic = nil
            self.txCharacteristic = nil
            self.rxBuffer.removeAll()
            self.state = .disconnected
        }
    }

    @discardableResult
    func sendCommand(_ jsonString: String) -> Bool {
        guard state == .connected,
              let peripheral = connectedPeripheral,
              let rxChar = rxCharacteristic,
              let data = (jsonString + "\n").data(using: .utf8) else {
            return false
        }

        queue.async {
            let writeType: CBCharacteristicWriteType = rxChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            let maxChunk = max(20, min(peripheral.maximumWriteValueLength(for: writeType), 180))
            var offset = 0
            while offset < data.count {
                let end = min(offset + maxChunk, data.count)
                let chunk = data.subdata(in: offset..<end)
                peripheral.writeValue(chunk, for: rxChar, type: writeType)
                offset = end
            }
        }
        return true
    }

    private func beginScanOrConnectIfReady() {
        lock.lock()
        let active = requested
        lock.unlock()
        guard active, let cm = centralManager else { return }

        guard cm.state == .poweredOn else {
            if cm.state == .poweredOff || cm.state == .unauthorized || cm.state == .unsupported {
                state = .disconnected
            } else {
                state = .connecting
            }
            return
        }

        if state == .connected, connectedPeripheral?.state == .connected, rxCharacteristic != nil {
            return
        }

        state = .connecting
        let retrieved = cm.retrieveConnectedPeripherals(withServices: [Self.serviceUuid])
        if let existing = retrieved.first {
            connectToPeripheral(existing)
            return
        }

        cm.scanForPeripherals(
            withServices: [Self.serviceUuid],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        centralManager?.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        rxBuffer.removeAll(keepingCapacity: true)
        centralManager?.connect(peripheral, options: nil)
    }

    private func startRescanWatchdog() {
        stopRescanWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 8.0, repeating: 8.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let active = self.requested
            self.lock.unlock()
            guard active else { return }
            if self.state != .connected {
                self.beginScanOrConnectIfReady()
            }
        }
        timer.resume()
        rescanTimer = timer
    }

    private func stopRescanWatchdog() {
        rescanTimer?.cancel()
        rescanTimer = nil
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        beginScanOrConnectIfReady()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        lock.lock()
        let active = requested
        lock.unlock()
        guard active else { return }
        if connectedPeripheral == nil || connectedPeripheral?.state != .connected {
            connectToPeripheral(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        rxBuffer.removeAll(keepingCapacity: true)
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUuid])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
            rxCharacteristic = nil
            txCharacteristic = nil
        }
        beginScanOrConnectIfReady()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
            rxCharacteristic = nil
            txCharacteristic = nil
            rxBuffer.removeAll()
        }
        lock.lock()
        let active = requested
        lock.unlock()
        if active {
            state = .connecting
            beginScanOrConnectIfReady()
        } else {
            state = .disconnected
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        for svc in services where svc.uuid == Self.serviceUuid {
            peripheral.discoverCharacteristics([Self.commandRxUuid, Self.telemetryTxUuid], for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        for ch in chars {
            if ch.uuid == Self.commandRxUuid {
                rxCharacteristic = ch
            } else if ch.uuid == Self.telemetryTxUuid {
                txCharacteristic = ch
                peripheral.setNotifyValue(true, for: ch)
            }
        }
        if rxCharacteristic != nil && txCharacteristic != nil {
            state = .connected
            onHeartbeatReceived?(Int64(Date().timeIntervalSince1970))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error == nil, characteristic.uuid == Self.telemetryTxUuid, characteristic.isNotifying, rxCharacteristic != nil {
            state = .connected
            onHeartbeatReceived?(Int64(Date().timeIntervalSince1970))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == Self.telemetryTxUuid,
              let chunk = characteristic.value,
              !chunk.isEmpty else {
            return
        }
        for byte in chunk {
            if byte == 0x0A { // '\n'
                if let line = String(data: rxBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    handleIncomingJsonLine(line)
                }
                rxBuffer.removeAll(keepingCapacity: true)
            } else if byte != 0x0D {
                if rxBuffer.count < 524_288 {
                    rxBuffer.append(byte)
                } else {
                    rxBuffer.removeAll(keepingCapacity: false)
                }
            }
        }
    }

    private func handleIncomingJsonLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        lock.lock()
        let curVin = expectedVin
        let curSecret = secretKey
        lock.unlock()

        let type = (json["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow HELLO with valid HMAC to sync VIN if local VIN is empty
        let verifyVin = (type == "HELLO" && curVin.isEmpty) ? "" : curVin
        guard WireEventVerifier.shared.verify(packet: json, expectedVin: verifyVin, secret: curSecret, retainedTelemetry: false) else {
            return
        }

        let nowSec = Int64(Date().timeIntervalSince1970)
        onHeartbeatReceived?(nowSec)

        if type == "HELLO" {
            let vehicleVin = (json["vin"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if vehicleVin.count == 17 {
                onVinSynced?(vehicleVin)
            }
            return
        }
        if type == "PONG" {
            return
        }

        let hasStatus = json["status"] != nil && !(json["status"] is NSNull)
        if type == "ACK" || (hasStatus && type.isEmpty) {
            onAckReceived?(json)
            return
        }
        if ["CAMERA_SNAPSHOT", "CAMERA_FRAME", "CAMERA_H264", "CABIN_AUDIO_FRAME", "MEDIA_STATUS"].contains(type) {
            onMediaReceived?(json)
            return
        }

        let parsed = TelemetryParser.parse(json, expectedVin: curVin)
        onTelemetryReceived?(parsed)
    }
}
