import Foundation

struct DiagnosticReading: Identifiable, Equatable {
    var id: String { "\(propertyId)_\(area)_\(name)" }
    let name: String
    let propertyId: String
    let area: Int
    let value: String?
}

struct DtcFaultItem: Identifiable, Equatable {
    var id: String { "\(system)_\(code)_\(description)" }
    let code: String
    let system: String
    let severity: String
    let description: String
}

struct EcuModuleItem: Identifiable, Equatable {
    var id: String { "\(code)_\(name)" }
    let code: String
    let name: String
    let status: String
}

enum BannerSeverity: Equatable {
    case pending
    case success
    case warning
    case error
    case info
}

struct CommandBannerState: Equatable {
    let id: Int64
    let message: String
    let severity: BannerSeverity
    var channelLabel: String? = nil
    var autoDismissMs: Int64 = 2600
}

enum LinkHealthState: String {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case reconnecting = "RECONNECTING"
    case connected = "CONNECTED"
}

struct ConnectionUiState: Equatable {
    var cloudState: LinkHealthState = .disconnected
    var btState: LinkHealthState = .disconnected
    var agentPresenceOnline: Bool = false
    var isReconnectingInGrace: Bool = false
    var isOnline: Bool = false
    var cloudLatencyMs: Int64? = nil
    var btLatencyMs: Int64? = nil
}

struct TelemetryState: Equatable {
    var energyMode: String = ""
    var standbyKeepalive: Bool = false
    var ventilationStatus: String = ""
    var diagnostics: [DiagnosticReading] = []
    var vin: String = ""

    var isBrokerConnected: Bool = false
    var isCloudTransportConnected: Bool = false
    var isLiveCloudSample: Bool = false
    var isPresenceOnline: Bool = false
    var isReconnectingGrace: Bool = false
    var isBluetoothConnected: Bool = false
    var isConnected: Bool = false

    var lastUpdateEpoch: Int64 = 0
    var lastCloudUpdateEpoch: Int64 = 0
    var lastBluetoothUpdateEpoch: Int64 = 0

    var ignitionState: Int = -1
    var ignitionDescription: String = "Məlumat yoxdur"
    var isCabinReady: Bool = false

    var batterySoc: Int = -1
    var evRangeKm: Int = -1
    var fuelRangeKm: Int = -1
    var totalRangeKm: Int = -1
    var isCharging: Bool = false

    var climatePower: Bool = false
    var targetTemp: Float = .nan
    var driverTemp: Float = .nan
    var passengerTemp: Float = .nan
    var isDualSync: Bool = true
    var fanSpeed: Int = -1
    var windMode: Int = -1
    var acCompressor: Bool = false
    var maxAc: Bool = false
    var autoMode: Bool = false
    var defrost: Bool = false
    var rearDefrost: Bool = false
    var recirculation: Bool = false
    var airPurifier: Bool = false
    var autoDefog: Bool = false
    var airDry: Bool = false
    var naturalWind: Bool = false
    var ecoClimate: Bool = false
    var smokeMode: Bool = false

    var wiperServiceMode: Bool = false
    var doorsLocked: Bool = false
    var windowsClosed: Bool = false
    var sunroofClosed: Bool = false
    var trunkClosed: Bool = false

    var tirePressureFl: Float = .nan
    var tirePressureFr: Float = .nan
    var tirePressureRl: Float = .nan
    var tirePressureRr: Float = .nan
    var tireStatusFl: String = ""
    var tireStatusFr: String = ""
    var tireStatusRl: String = ""
    var tireStatusRr: String = ""
    var tpmsMode: String = ""
    var tireTempFl: Int = -1000
    var tireTempFr: Int = -1000
    var tireTempRl: Int = -1000
    var tireTempRr: Int = -1000

    var fuelPercent: Int = -1
    var cameraIds: [String] = []
    var latitude: Double = .nan
    var longitude: Double = .nan
    var locationEpoch: Int64 = 0
    var locationAccuracy: Float = .nan
    var windowPositions: [Int] = [-1, -1, -1, -1]
    var sunroofPosition: Int = -1
    var supportedActions: Set<String> = []
    var unavailableFields: Set<String> = []

    var outsideTemp: Float = .nan
    var cabinTemp: Float = .nan
    var vehicleSpeed: Float = .nan
    var odometerKm: Float = .nan
    var gear: String = ""
    var parkingBrake: Bool? = nil
    var batteryVoltage12V: Float = .nan

    var doorFlOpen: Bool = false
    var doorFrOpen: Bool = false
    var doorRlOpen: Bool = false
    var doorRrOpen: Bool = false
    var hoodOpen: Bool = false
    var trunkOpen: Bool = false
    var fuelDoorOpen: Bool? = nil

    // Engine Sound
    var engineSoundEnabled: Bool = false
    var engineSoundProfile: String = "BMW_M_V8"
    var engineSoundVolume: String = "normal"
    var virtualRpm: Int = 0
    var throttlePercent: Int = -1

    // Light Show
    var lightShowActive: Bool = false
    var lightShowProfile: String = "BEAT_SYNC"
    var lightShowRoute: String = "DUAL"
    var lightShowTrack: String = "user_hero"
    var lightShowHeadlights: Bool = true
    var lightShowHighBeams: Bool = true
    var lightShowTurnSignals: Bool = true
    var lightShowWidthLamps: Bool = true
    var lightShowVentWindows: Bool = false
    var lightShowBcmGate: Int = -1
    var lightShowDirectFallback: Bool = false

    // PHEV / BMS
    var batterySoh: Float = .nan
    var hvVoltage: Float = .nan
    var hvCurrent: Float = .nan
    var hvPowerKw: Float = .nan
    var regenPowerKw: Float = .nan
    var cellMinMv: Int = -1
    var cellMaxMv: Int = -1
    var cellDeltaMv: Int = -1
    var batteryTempMin: Float = .nan
    var batteryTempMax: Float = .nan
    var chargeCycles: Int = -1
    var packCapacityKwh: Float = 18.99
    var batteryChemistry: String = "LiFePO4 (LFP · 96S)"
    var isRatedSpec: Bool = true
    var saveTargetSoc: Int = -1
    var chargeMaxSoc: Int = -1
    var fuelLevelLow: Bool? = nil
    var saveFuelLitres: Float = .nan
    var chargePortOpen: Bool? = nil
    var chargePortConnected: Bool? = nil
    var chargeRateKw: Float = .nan
    var energyFlowMode: Int = -1
    var chargeDisMode: Int = -1

    // Air Quality
    var pm25Inside: Int = -1
    var pm25Outside: Int = -1
    var airQualityLevel: String = ""
    var aqsEnabled: Bool = false
    var ionizerEnabled: Bool = false
    var aqsState: Bool? = nil
    var ionizerState: Bool? = nil

    // Diagnostics / OBD
    var coolantTempC: Float = .nan
    var oilTempC: Float = .nan
    var oilPressureStatus: String = ""
    var oilInfoRaw: Int = -1
    var inverterTempC: Float = .nan
    var motorTempC: Float = .nan
    var engineRpm: Int = -1
    var dtcCodes: [DtcFaultItem] = []
    var panelWarnings: [DtcFaultItem] = []
    var ecuModules: [EcuModuleItem] = []
    var warningChannelsCount: Int = -1
    var faultChannelsCount: Int = -1

    // Lights & Safety & Drive mode
    var headlightsOn: Bool = false
    var selektorOn: Bool = false
    var decorativeLightOn: Bool = false
    var fogLightsOn: Bool = false
    var domeLightOn: Bool = false
    var ambientLightOn: Bool = false
    var ambientBrightness: Int = 5
    var ambientColor: Int = 1
    var driveMode: String = "NORMAL"
    var driveSubMode: String = ""
    var safetyArmed: Bool = false
    var safetyAlarmTriggered: Bool = false

    // Sensors & DVR
    var autoHold: Bool? = nil
    var absActive: Bool? = nil
    var tcsActive: Bool? = nil
    var steeringAngleRaw: Float = .nan
    var fuelConsumptionAvg: Float = .nan
    var nightMode: Bool? = nil
    var rainLevel: Int = -1
    var wirelessCharging: Bool? = nil
    var sunshadePosition: Int = -1
    var seatbeltDriverRaw: Int = -1
    var seatbeltPassengerRaw: Int = -1
    var seatbeltRlRaw: Int = -1
    var seatbeltRcRaw: Int = -1
    var seatbeltRrRaw: Int = -1
    var dvrStoragePercent: Int = -1
    var dvrSdError: Bool? = nil
    var dvrSdFull: Bool? = nil

    // Head Unit / System / GPS
    var gpsEnabled: Bool? = nil
    var altitudeM: Double = .nan
    var gpsSpeedKmh: Float = .nan
    var bearingDeg: Float = .nan
    var gpsSatellites: Int = -1
    var agentVersion: String = ""
    var androidVersion: String = ""
    var deviceModel: String = ""
    var uptimeSec: Int64 = -1
    var ramFreeMb: Int = -1
    var ramTotalMb: Int = -1
    var storageFreeMb: Int = -1
    var storageTotalMb: Int = -1
    var networkTransport: String = ""
    var wifiEnabled: Bool? = nil
    var wifiSsid: String = ""
    var wifiRssiDbm: Int? = nil
    var wifiIp: String = ""
    var bluetoothEnabled: Bool? = nil
    var mcuVersion: String = ""
    var dspVersion: String = ""
    var hwVersion: String = ""
    var tboxIccid: String = ""
    var oemConnected: Bool? = nil

    // Agent settings
    var agentAutoMuteAvas: Bool? = nil
    var agentLockChimeEnabled: Bool? = nil
    var agentLockVolumePct: Int = -1
    var agentSirenVolumePct: Int = -1
    var agentEngineVolumePct: Int = -1
    var agentMegaphoneVolumePct: Int = -1
    var agentLsAvasVolumePct: Int = -1
    var agentLsCabinVolumePct: Int = -1
    var agentRadioRecovery: Bool? = nil
    var agentAutoClimate: Bool? = nil
    var agentVehiclePlate: String = ""

    func isCloudLive(nowSeconds: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        guard isCloudTransportConnected else { return false }
        if isPresenceOnline { return true }
        let delta = nowSeconds - lastCloudUpdateEpoch
        return isBrokerConnected && lastCloudUpdateEpoch > 0 && delta >= -30 && delta <= CommandProtocol.telemetryOnlineStaleSeconds
    }

    func isBluetoothLive(nowSeconds: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        guard isBluetoothConnected else { return false }
        if lastBluetoothUpdateEpoch == 0 { return true }
        let delta = nowSeconds - lastBluetoothUpdateEpoch
        return delta >= -30 && delta <= CommandProtocol.telemetryOnlineStaleSeconds
    }

    func isTrulyOnline(nowSeconds: Int64 = Int64(Date().timeIntervalSince1970)) -> Bool {
        isBluetoothLive(nowSeconds: nowSeconds) || isCloudLive(nowSeconds: nowSeconds)
    }

    func lastSeenDescription() -> String {
        guard lastUpdateEpoch > 0 else { return "Məlumat alınmayıb" }
        let now = Int64(Date().timeIntervalSince1970)
        let diff = max(0, now - lastUpdateEpoch)
        if diff < 5 { return "İndi" }
        if diff < 60 { return "\(diff) san. əvvəl" }
        if diff < 3600 { return "\(diff / 60) dəq. əvvəl" }
        return "\(diff / 3600) saat əvvəl"
    }

    func mergeWithPrevious(_ previous: TelemetryState) -> TelemetryState {
        if !previous.vin.isEmpty && !vin.isEmpty && previous.vin.caseInsensitiveCompare(vin) != .orderedSame {
            return self
        }
        var restoredFields: Set<String> = []
        let hasPrevious = previous.lastUpdateEpoch > 0

        func keepBool(_ field: String, _ current: Bool, _ prev: Bool) -> Bool {
            if hasPrevious && unavailableFields.contains(field) && !previous.unavailableFields.contains(field) {
                restoredFields.insert(field)
                return prev
            }
            return current
        }

        func keepInt(_ field: String, _ valid: Bool, _ current: Int, _ prev: Int, aliases: [String] = []) -> Int {
            if valid { return current }
            if hasPrevious && (prev >= 0 || !previous.unavailableFields.contains(field)) {
                restoredFields.insert(field)
                for a in aliases { restoredFields.insert(a) }
            }
            return prev
        }

        func keepFloat(_ field: String, _ current: Float, _ prev: Float, aliases: [String] = []) -> Float {
            if current.isFinite { return current }
            if hasPrevious && prev.isFinite {
                restoredFields.insert(field)
                for a in aliases { restoredFields.insert(a) }
            }
            return prev
        }

        func keepNullableBool(_ field: String, _ current: Bool?, _ prev: Bool?) -> Bool? {
            if let current { return current }
            if hasPrevious && prev != nil { restoredFields.insert(field) }
            return prev
        }

        func keepSignedInt(_ field: String, _ current: Int, _ prev: Int, minValid: Int) -> Int {
            let curValid = current >= minValid && !unavailableFields.contains(field)
            if curValid { return current }
            let prevValid = prev >= minValid && !previous.unavailableFields.contains(field)
            if hasPrevious && prevValid {
                restoredFields.insert(field)
                return prev
            }
            return prev
        }

        let windowKeys = ["body.windowfl", "body.windowfr", "body.windowrl", "body.windowrr"]
        let mergedWindows: [Int] = (0..<4).map { idx in
            let v = idx < windowPositions.count ? windowPositions[idx] : -1
            if v >= 0 { return v }
            let pv = idx < previous.windowPositions.count ? previous.windowPositions[idx] : -1
            if hasPrevious && pv >= 0 { restoredFields.insert(windowKeys[idx]) }
            return pv
        }
        let mergedRoof = keepInt("body.sunroofPosition", sunroofPosition >= 0, sunroofPosition, previous.sunroofPosition)
        let mergedTrunkOpen = keepBool("body.trunkOpen", trunkOpen, previous.trunkOpen)
        let mergedWindowsClosed: Bool
        if mergedWindows.allSatisfy({ $0 >= 0 }) {
            restoredFields.insert("body.windowsClosed")
            mergedWindowsClosed = mergedWindows.allSatisfy { $0 == 0 }
        } else {
            mergedWindowsClosed = keepBool("body.windowsClosed", windowsClosed, previous.windowsClosed)
        }
        let mergedSunroofClosed: Bool
        if mergedRoof >= 0 {
            restoredFields.insert("body.sunroofClosed")
            mergedSunroofClosed = mergedRoof == 0
        } else {
            mergedSunroofClosed = keepBool("body.sunroofClosed", sunroofClosed, previous.sunroofClosed)
        }
        let mergedTrunkClosed: Bool
        if !unavailableFields.contains("body.trunkOpen") || restoredFields.contains("body.trunkOpen") {
            restoredFields.insert("body.trunkClosed")
            mergedTrunkClosed = !mergedTrunkOpen
        } else {
            mergedTrunkClosed = keepBool("body.trunkClosed", trunkClosed, previous.trunkClosed)
        }

        let mergedEvRange = keepInt("phev.evRangeKm", evRangeKm >= 0, evRangeKm, previous.evRangeKm)
        let mergedFuelRange = keepInt("phev.fuelRangeKm", fuelRangeKm >= 0, fuelRangeKm, previous.fuelRangeKm)
        let explicitTotal = keepInt("phev.totalRangeKm", totalRangeKm >= 0, totalRangeKm, previous.totalRangeKm)

        var out = self
        out.energyMode = energyMode.isEmpty ? previous.energyMode : energyMode
        out.ignitionState = keepInt("ignition.state", ignitionState >= 0, ignitionState, previous.ignitionState)
        out.ignitionDescription = ignitionState >= 0 ? ignitionDescription : previous.ignitionDescription
        out.isCabinReady = keepBool("ignition.isCabinReady", isCabinReady, previous.isCabinReady)
        out.batterySoc = keepInt("phev.batterySoc", (0...100).contains(batterySoc), batterySoc, previous.batterySoc, aliases: ["phev.socPercent"])
        out.fuelPercent = keepInt("phev.fuelLevelPercent", (0...100).contains(fuelPercent), fuelPercent, previous.fuelPercent, aliases: ["phev.fuelPercent"])
        out.evRangeKm = mergedEvRange
        out.fuelRangeKm = mergedFuelRange
        out.totalRangeKm = explicitTotal >= 0 ? explicitTotal : (mergedEvRange >= 0 && mergedFuelRange >= 0 ? mergedEvRange + mergedFuelRange : -1)
        out.isCharging = keepBool("phev.isCharging", isCharging, previous.isCharging)

        out.climatePower = keepBool("climate.power", climatePower, previous.climatePower)
        out.targetTemp = keepFloat("climate.targetTemp", targetTemp, previous.targetTemp, aliases: ["climate.driverTemp"])
        out.driverTemp = keepFloat("climate.driverTemp", driverTemp, previous.driverTemp, aliases: ["climate.targetTemp"])
        out.passengerTemp = keepFloat("climate.passengerTemp", passengerTemp, previous.passengerTemp)
        out.fanSpeed = keepInt("climate.fanSpeed", fanSpeed >= 0, fanSpeed, previous.fanSpeed)
        out.windMode = keepInt("climate.windMode", windMode >= 0, windMode, previous.windMode)
        out.acCompressor = keepBool("climate.acCompressor", acCompressor, previous.acCompressor)
        out.maxAc = keepBool("climate.maxAc", maxAc, previous.maxAc)
        out.autoMode = keepBool("climate.autoMode", autoMode, previous.autoMode)
        out.defrost = keepBool("climate.defrost", defrost, previous.defrost)
        out.rearDefrost = keepBool("climate.rearDefrost", rearDefrost, previous.rearDefrost)
        out.recirculation = keepBool("climate.recirculation", recirculation, previous.recirculation)
        out.airPurifier = keepBool("climate.airPurifier", airPurifier, previous.airPurifier)
        out.autoDefog = keepBool("climate.autoDefog", autoDefog, previous.autoDefog)
        out.airDry = keepBool("climate.airDry", airDry, previous.airDry)
        out.naturalWind = keepBool("climate.naturalWind", naturalWind, previous.naturalWind)
        out.ecoClimate = keepBool("climate.ecoMode", ecoClimate, previous.ecoClimate)
        out.smokeMode = keepBool("climate.smokeMode", smokeMode, previous.smokeMode)

        out.outsideTemp = keepFloat("sensors.outsideTemp", outsideTemp, previous.outsideTemp)
        out.cabinTemp = keepFloat("sensors.cabinTemp", cabinTemp, previous.cabinTemp)
        out.vehicleSpeed = keepFloat("sensors.speedKmH", vehicleSpeed, previous.vehicleSpeed)
        out.odometerKm = keepFloat("sensors.odometerKm", odometerKm, previous.odometerKm)
        out.gear = gear.isEmpty ? previous.gear : gear
        out.parkingBrake = keepNullableBool("sensors.parkingBrake", parkingBrake, previous.parkingBrake)
        out.batteryVoltage12V = keepFloat("sensors.battery12V", batteryVoltage12V, previous.batteryVoltage12V, aliases: ["deepDiagnostics.battery12vVolts"])

        out.wiperServiceMode = keepBool("body.wiperServiceMode", wiperServiceMode, previous.wiperServiceMode)
        out.doorsLocked = keepBool("body.doorsLocked", doorsLocked, previous.doorsLocked)
        out.doorFlOpen = keepBool("body.doorFlOpen", doorFlOpen, previous.doorFlOpen)
        out.doorFrOpen = keepBool("body.doorFrOpen", doorFrOpen, previous.doorFrOpen)
        out.doorRlOpen = keepBool("body.doorRlOpen", doorRlOpen, previous.doorRlOpen)
        out.doorRrOpen = keepBool("body.doorRrOpen", doorRrOpen, previous.doorRrOpen)
        out.hoodOpen = keepBool("body.hoodOpen", hoodOpen, previous.hoodOpen)
        out.trunkOpen = mergedTrunkOpen
        out.fuelDoorOpen = keepNullableBool("body.fuelDoorOpen", fuelDoorOpen, previous.fuelDoorOpen)

        out.windowPositions = mergedWindows
        out.sunroofPosition = mergedRoof
        out.windowsClosed = mergedWindowsClosed
        out.sunroofClosed = mergedSunroofClosed
        out.trunkClosed = mergedTrunkClosed

        out.tirePressureFl = keepFloat("tires.pressureFl", tirePressureFl, previous.tirePressureFl)
        out.tirePressureFr = keepFloat("tires.pressureFr", tirePressureFr, previous.tirePressureFr)
        out.tirePressureRl = keepFloat("tires.pressureRl", tirePressureRl, previous.tirePressureRl)
        out.tirePressureRr = keepFloat("tires.pressureRr", tirePressureRr, previous.tirePressureRr)
        out.tireStatusFl = tireStatusFl.isEmpty ? previous.tireStatusFl : tireStatusFl
        out.tireStatusFr = tireStatusFr.isEmpty ? previous.tireStatusFr : tireStatusFr
        out.tireStatusRl = tireStatusRl.isEmpty ? previous.tireStatusRl : tireStatusRl
        out.tireStatusRr = tireStatusRr.isEmpty ? previous.tireStatusRr : tireStatusRr
        out.tpmsMode = tpmsMode.isEmpty ? previous.tpmsMode : tpmsMode
        out.tireTempFl = keepSignedInt("tires.tempFl", tireTempFl, previous.tireTempFl, minValid: -50)
        out.tireTempFr = keepSignedInt("tires.tempFr", tireTempFr, previous.tireTempFr, minValid: -50)
        out.tireTempRl = keepSignedInt("tires.tempRl", tireTempRl, previous.tireTempRl, minValid: -50)
        out.tireTempRr = keepSignedInt("tires.tempRr", tireTempRr, previous.tireTempRr, minValid: -50)

        out.cameraIds = cameraIds.isEmpty ? previous.cameraIds : cameraIds
        out.supportedActions = supportedActions.isEmpty ? previous.supportedActions : supportedActions
        out.latitude = latitude.isFinite ? latitude : previous.latitude
        out.longitude = longitude.isFinite ? longitude : previous.longitude
        out.locationEpoch = locationEpoch > 0 ? locationEpoch : previous.locationEpoch
        out.locationAccuracy = keepFloat("location.accuracy", locationAccuracy, previous.locationAccuracy)

        out.batterySoh = batterySoh.isFinite ? batterySoh : previous.batterySoh
        out.hvVoltage = hvVoltage.isFinite ? hvVoltage : previous.hvVoltage
        out.hvCurrent = hvCurrent.isFinite ? hvCurrent : previous.hvCurrent
        out.hvPowerKw = hvPowerKw.isFinite ? hvPowerKw : previous.hvPowerKw
        out.regenPowerKw = regenPowerKw.isFinite ? regenPowerKw : previous.regenPowerKw
        out.cellMinMv = cellMinMv >= 0 ? cellMinMv : previous.cellMinMv
        out.cellMaxMv = cellMaxMv >= 0 ? cellMaxMv : previous.cellMaxMv
        out.cellDeltaMv = cellDeltaMv >= 0 ? cellDeltaMv : previous.cellDeltaMv
        out.batteryTempMin = batteryTempMin.isFinite ? batteryTempMin : previous.batteryTempMin
        out.batteryTempMax = batteryTempMax.isFinite ? batteryTempMax : previous.batteryTempMax
        out.chargeCycles = chargeCycles >= 0 ? chargeCycles : previous.chargeCycles
        out.saveTargetSoc = (0...100).contains(saveTargetSoc) ? saveTargetSoc : previous.saveTargetSoc
        out.chargeMaxSoc = (0...100).contains(chargeMaxSoc) ? chargeMaxSoc : previous.chargeMaxSoc
        out.fuelLevelLow = keepNullableBool("phev.fuelLevelLow", fuelLevelLow, previous.fuelLevelLow)
        out.saveFuelLitres = keepFloat("phev.saveFuelLitres", saveFuelLitres, previous.saveFuelLitres)
        out.chargePortOpen = keepNullableBool("phev.chargePortOpen", chargePortOpen, previous.chargePortOpen)
        out.chargePortConnected = keepNullableBool("phev.chargePortConnected", chargePortConnected, previous.chargePortConnected)
        out.chargeRateKw = keepFloat("phev.chargeRateKw", chargeRateKw, previous.chargeRateKw)

        out.pm25Inside = pm25Inside >= 0 ? pm25Inside : previous.pm25Inside
        out.pm25Outside = pm25Outside >= 0 ? pm25Outside : previous.pm25Outside
        out.airQualityLevel = airQualityLevel.isEmpty ? previous.airQualityLevel : airQualityLevel
        out.aqsEnabled = keepBool("airQuality.aqsEnabled", aqsEnabled, previous.aqsEnabled)
        out.ionizerEnabled = keepBool("airQuality.ionizerEnabled", ionizerEnabled, previous.ionizerEnabled)
        out.aqsState = aqsState ?? previous.aqsState
        out.ionizerState = ionizerState ?? previous.ionizerState

        out.coolantTempC = keepFloat("sensors.coolantTemp", coolantTempC, previous.coolantTempC, aliases: ["deepDiagnostics.coolantTempC"])
        out.oilTempC = keepFloat("deepDiagnostics.oilTempC", oilTempC, previous.oilTempC, aliases: ["sensors.oilTemp"])
        out.oilPressureStatus = oilPressureStatus.isEmpty ? previous.oilPressureStatus : oilPressureStatus
        out.oilInfoRaw = keepInt("sensors.oilInfoRaw", oilInfoRaw >= 0, oilInfoRaw, previous.oilInfoRaw, aliases: ["deepDiagnostics.oilInfoRaw"])
        out.inverterTempC = keepFloat("deepDiagnostics.inverterTempC", inverterTempC, previous.inverterTempC)
        out.motorTempC = keepFloat("deepDiagnostics.motorTempC", motorTempC, previous.motorTempC)
        out.engineRpm = keepInt("sensors.engineRpm", engineRpm >= 0, engineRpm, previous.engineRpm)

        out.headlightsOn = keepBool("lights.headlights", headlightsOn, previous.headlightsOn)
        out.selektorOn = keepBool("lights.selektor", selektorOn, previous.selektorOn)
        out.decorativeLightOn = keepBool("lights.decorativeLight", decorativeLightOn, previous.decorativeLightOn)
        out.fogLightsOn = keepBool("lights.fogLights", fogLightsOn, previous.fogLightsOn)
        out.domeLightOn = keepBool("lights.domeLight", domeLightOn, previous.domeLightOn)
        out.ambientLightOn = keepBool("lights.ambientLight", ambientLightOn, previous.ambientLightOn)
        out.ambientBrightness = !unavailableFields.contains("lights.ambientBrightness") ? ambientBrightness : previous.ambientBrightness
        out.ambientColor = !unavailableFields.contains("lights.ambientColor") ? ambientColor : previous.ambientColor
        out.driveMode = driveMode.isEmpty ? previous.driveMode : driveMode
        out.driveSubMode = !unavailableFields.contains("sensors.driveSubMode") ? driveSubMode : previous.driveSubMode

        out.autoHold = keepNullableBool("sensors.autoHold", autoHold, previous.autoHold)
        out.absActive = keepNullableBool("sensors.absActive", absActive, previous.absActive)
        out.tcsActive = keepNullableBool("sensors.tcsActive", tcsActive, previous.tcsActive)
        out.steeringAngleRaw = keepFloat("sensors.steeringAngleRaw", steeringAngleRaw, previous.steeringAngleRaw)
        out.fuelConsumptionAvg = keepFloat("sensors.fuelConsumptionAvg", fuelConsumptionAvg, previous.fuelConsumptionAvg)
        out.nightMode = keepNullableBool("sensors.nightMode", nightMode, previous.nightMode)
        out.rainLevel = keepInt("sensors.rainLevel", rainLevel >= 0, rainLevel, previous.rainLevel)
        out.wirelessCharging = keepNullableBool("sensors.wirelessCharging", wirelessCharging, previous.wirelessCharging)
        out.sunshadePosition = keepInt("body.sunshadePosition", sunshadePosition >= 0, sunshadePosition, previous.sunshadePosition)
        out.dvrStoragePercent = keepInt("dvr.storagePercent", dvrStoragePercent >= 0, dvrStoragePercent, previous.dvrStoragePercent)
        out.dvrSdError = keepNullableBool("dvr.sdError", dvrSdError, previous.dvrSdError)
        out.dvrSdFull = keepNullableBool("dvr.sdFull", dvrSdFull, previous.dvrSdFull)

        out.dtcCodes = dtcCodes.isEmpty ? previous.dtcCodes : dtcCodes
        out.panelWarnings = panelWarnings.isEmpty ? previous.panelWarnings : panelWarnings
        out.ecuModules = ecuModules.isEmpty ? previous.ecuModules : ecuModules
        out.diagnostics = diagnostics.isEmpty ? previous.diagnostics : diagnostics

        out.agentAutoMuteAvas = agentAutoMuteAvas ?? previous.agentAutoMuteAvas
        out.agentLockChimeEnabled = agentLockChimeEnabled ?? previous.agentLockChimeEnabled
        out.agentLockVolumePct = agentLockVolumePct >= 0 ? agentLockVolumePct : previous.agentLockVolumePct
        out.agentSirenVolumePct = agentSirenVolumePct >= 0 ? agentSirenVolumePct : previous.agentSirenVolumePct
        out.agentEngineVolumePct = agentEngineVolumePct >= 0 ? agentEngineVolumePct : previous.agentEngineVolumePct
        out.agentMegaphoneVolumePct = agentMegaphoneVolumePct >= 0 ? agentMegaphoneVolumePct : previous.agentMegaphoneVolumePct
        out.agentLsAvasVolumePct = agentLsAvasVolumePct >= 0 ? agentLsAvasVolumePct : previous.agentLsAvasVolumePct
        out.agentLsCabinVolumePct = agentLsCabinVolumePct >= 0 ? agentLsCabinVolumePct : previous.agentLsCabinVolumePct
        out.agentRadioRecovery = agentRadioRecovery ?? previous.agentRadioRecovery
        out.agentAutoClimate = agentAutoClimate ?? previous.agentAutoClimate
        out.agentVehiclePlate = agentVehiclePlate.isEmpty ? previous.agentVehiclePlate : agentVehiclePlate
        out.unavailableFields = unavailableFields.subtracting(restoredFields)
        return out
    }
}
