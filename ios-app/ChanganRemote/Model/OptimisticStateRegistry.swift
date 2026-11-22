import Foundation

final class OptimisticStateRegistry {
    private struct LockEntry {
        let key: String
        let expectedValue: Any
        let expiresAt: Date
        var msgId: String?
    }

    private let lock = NSLock()
    private var entries: [String: LockEntry] = [:]
    private let defaultHoldSeconds: TimeInterval

    init(defaultHoldSeconds: TimeInterval = 5.0) {
        self.defaultHoldSeconds = defaultHoldSeconds
    }

    func lockKey(_ key: String, expectedValue: Any, holdSeconds: TimeInterval? = nil, msgId: String? = nil) {
        let dur = holdSeconds ?? defaultHoldSeconds
        lock.lock()
        entries[key] = LockEntry(key: key, expectedValue: expectedValue, expiresAt: Date().addingTimeInterval(dur), msgId: msgId)
        lock.unlock()
    }

    func attachMsgId(_ keys: Set<String>, msgId: String) {
        lock.lock()
        for key in keys {
            if var existing = entries[key], existing.msgId == nil {
                existing.msgId = msgId
                entries[key] = existing
            }
        }
        lock.unlock()
    }

    func releaseByMsgId(_ msgId: String) {
        lock.lock()
        entries = entries.filter { $0.value.msgId != msgId }
        lock.unlock()
    }

    func releaseKeys(_ keys: Set<String>, onlyUnattached: Bool = false) {
        lock.lock()
        for key in keys {
            if onlyUnattached {
                if let existing = entries[key], existing.msgId == nil {
                    entries.removeValue(forKey: key)
                }
            } else {
                entries.removeValue(forKey: key)
            }
        }
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    func applyTo(_ incoming: TelemetryState) -> TelemetryState {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { now < $0.value.expiresAt }
        guard !entries.isEmpty else { return incoming }

        var state = incoming
        var keysToRemove: [String] = []

        for (key, entry) in entries {
            let v = entry.expectedValue
            let matches: Bool
            switch key {
            case "doorsLocked":
                matches = state.doorsLocked == (v as? Bool)
            case "windowPositions":
                if let target = v as? Int {
                    if target == 0 {
                        matches = state.windowPositions.allSatisfy { $0 == 0 }
                    } else {
                        matches = state.windowPositions.allSatisfy { $0 >= 0 && abs($0 - target) <= 6 }
                    }
                } else {
                    matches = false
                }
            case "windowPos_0", "windowPos_1", "windowPos_2", "windowPos_3":
                let idx = Int(key.split(separator: "_").last ?? "") ?? -1
                if let target = v as? Int, (0..<state.windowPositions.count).contains(idx) {
                    let cur = state.windowPositions[idx]
                    matches = target == 0 ? cur == 0 : ((0...100).contains(cur) && abs(cur - target) <= 6)
                } else {
                    matches = false
                }
            case "sunroofPosition":
                if let target = v as? Int {
                    switch target {
                    case 0: matches = state.sunroofPosition == 0
                    case 101: matches = state.sunroofPosition == 101
                    default: matches = (1...100).contains(state.sunroofPosition) && abs(state.sunroofPosition - target) <= 10
                    }
                } else {
                    matches = false
                }
            case "headlightsOn": matches = state.headlightsOn == (v as? Bool)
            case "selektorOn": matches = state.selektorOn == (v as? Bool)
            case "decorativeLightOn": matches = state.decorativeLightOn == (v as? Bool)
            case "fogLightsOn": matches = state.fogLightsOn == (v as? Bool)
            case "domeLightOn": matches = state.domeLightOn == (v as? Bool)
            case "ambientLightOn": matches = state.ambientLightOn == (v as? Bool)
            case "ambientBrightness": matches = state.ambientBrightness == (v as? Int)
            case "ambientColor": matches = state.ambientColor == (v as? Int)
            case "wiperServiceMode": matches = state.wiperServiceMode == (v as? Bool)
            case "driveMode":
                let combined = state.driveSubMode.isEmpty ? state.driveMode : "\(state.driveMode)_\(state.driveSubMode)"
                matches = state.driveMode == (v as? String) || combined == (v as? String)
            case "saveTargetSoc": matches = state.saveTargetSoc == (v as? Int)
            case "safetyArmed": matches = state.safetyArmed == (v as? Bool)
            case "standbyKeepalive": matches = state.standbyKeepalive == (v as? Bool)
            case "agentAutoMuteAvas": matches = state.agentAutoMuteAvas == (v as? Bool)
            case "agentLockChimeEnabled": matches = state.agentLockChimeEnabled == (v as? Bool)
            case "agentRadioRecovery": matches = state.agentRadioRecovery == (v as? Bool)
            case "agentAutoClimate": matches = state.agentAutoClimate == (v as? Bool)
            case "climatePower": matches = state.climatePower == (v as? Bool)
            case "fanSpeed": matches = state.fanSpeed == (v as? Int)
            case "windMode":
                let target = v as? Int
                matches = state.windMode == target || (target == 4 && state.windMode == 6)
            case "driverTemp":
                if let target = v as? Float {
                    matches = state.driverTemp.isFinite && abs(state.driverTemp - target) < 0.25
                } else { matches = false }
            case "passengerTemp":
                if let target = v as? Float {
                    matches = state.passengerTemp.isFinite && abs(state.passengerTemp - target) < 0.25
                } else { matches = false }
            case "acCompressor": matches = state.acCompressor == (v as? Bool)
            case "maxAc": matches = state.maxAc == (v as? Bool)
            case "autoMode": matches = state.autoMode == (v as? Bool)
            case "defrost": matches = state.defrost == (v as? Bool)
            case "rearDefrost": matches = state.rearDefrost == (v as? Bool)
            case "recirculation": matches = state.recirculation == (v as? Bool)
            case "autoDefog": matches = state.autoDefog == (v as? Bool)
            case "airDry": matches = state.airDry == (v as? Bool)
            case "naturalWind": matches = state.naturalWind == (v as? Bool)
            case "ecoClimate": matches = state.ecoClimate == (v as? Bool)
            case "smokeMode": matches = state.smokeMode == (v as? Bool)
            case "engineSoundEnabled": matches = state.engineSoundEnabled == (v as? Bool)
            default: matches = true
            }

            if matches {
                keysToRemove.append(key)
                continue
            }

            switch key {
            case "doorsLocked": if let b = v as? Bool { state.doorsLocked = b }
            case "windowPositions":
                if let t = v as? Int {
                    state.windowPositions = [t, t, t, t]
                    state.windowsClosed = (t == 0)
                }
            case "windowPos_0", "windowPos_1", "windowPos_2", "windowPos_3":
                if let t = v as? Int, let idx = Int(key.split(separator: "_").last ?? ""), (0...3).contains(idx) {
                    while state.windowPositions.count < 4 { state.windowPositions.append(0) }
                    state.windowPositions[idx] = t
                    state.windowsClosed = state.windowPositions.allSatisfy { $0 == 0 }
                }
            case "sunroofPosition":
                if let t = v as? Int {
                    state.sunroofPosition = t
                    state.sunroofClosed = (t == 0)
                }
            case "headlightsOn": if let b = v as? Bool { state.headlightsOn = b }
            case "selektorOn": if let b = v as? Bool { state.selektorOn = b }
            case "decorativeLightOn": if let b = v as? Bool { state.decorativeLightOn = b }
            case "fogLightsOn": if let b = v as? Bool { state.fogLightsOn = b }
            case "domeLightOn": if let b = v as? Bool { state.domeLightOn = b }
            case "ambientLightOn": if let b = v as? Bool { state.ambientLightOn = b }
            case "ambientBrightness": if let i = v as? Int { state.ambientBrightness = i }
            case "ambientColor": if let i = v as? Int { state.ambientColor = i }
            case "wiperServiceMode": if let b = v as? Bool { state.wiperServiceMode = b }
            case "driveMode":
                if let target = v as? String {
                    let parts = target.split(separator: "_", maxSplits: 1).map(String.init)
                    state.driveMode = parts.first ?? target
                    state.driveSubMode = parts.count > 1 ? parts[1] : ""
                }
            case "saveTargetSoc": if let i = v as? Int { state.saveTargetSoc = i }
            case "safetyArmed": if let b = v as? Bool { state.safetyArmed = b }
            case "standbyKeepalive": if let b = v as? Bool { state.standbyKeepalive = b }
            case "agentAutoMuteAvas": if let b = v as? Bool { state.agentAutoMuteAvas = b }
            case "agentLockChimeEnabled": if let b = v as? Bool { state.agentLockChimeEnabled = b }
            case "agentRadioRecovery": if let b = v as? Bool { state.agentRadioRecovery = b }
            case "agentAutoClimate": if let b = v as? Bool { state.agentAutoClimate = b }
            case "climatePower": if let b = v as? Bool { state.climatePower = b }
            case "fanSpeed": if let i = v as? Int { state.fanSpeed = i }
            case "windMode": if let i = v as? Int { state.windMode = i }
            case "driverTemp": if let f = v as? Float { state.driverTemp = f; state.targetTemp = f }
            case "passengerTemp": if let f = v as? Float { state.passengerTemp = f }
            case "acCompressor": if let b = v as? Bool { state.acCompressor = b }
            case "maxAc": if let b = v as? Bool { state.maxAc = b }
            case "autoMode": if let b = v as? Bool { state.autoMode = b }
            case "defrost": if let b = v as? Bool { state.defrost = b }
            case "rearDefrost": if let b = v as? Bool { state.rearDefrost = b }
            case "recirculation": if let b = v as? Bool { state.recirculation = b }
            case "autoDefog": if let b = v as? Bool { state.autoDefog = b }
            case "airDry": if let b = v as? Bool { state.airDry = b }
            case "naturalWind": if let b = v as? Bool { state.naturalWind = b }
            case "ecoClimate": if let b = v as? Bool { state.ecoClimate = b }
            case "smokeMode": if let b = v as? Bool { state.smokeMode = b }
            case "engineSoundEnabled": if let b = v as? Bool { state.engineSoundEnabled = b }
            default: break
            }
        }

        for k in keysToRemove { entries.removeValue(forKey: k) }
        return state
    }
}
