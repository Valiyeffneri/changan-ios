import Foundation

enum TelemetryParser {
    static func parse(_ root: [String: Any], expectedVin: String) -> TelemetryState {
        let packetVin = (root["vin"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let exp = expectedVin.trimmingCharacters(in: .whitespacesAndNewlines)
        var unavailable = Set((root["unavailableFields"] as? [String]) ?? [])

        func value(_ path: String) -> Any? {
            let parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            var cursor: Any? = root
            for part in parts {
                guard let dict = cursor as? [String: Any], let next = dict[part], !(next is NSNull) else {
                    unavailable.insert(path)
                    return nil
                }
                cursor = next
            }
            return cursor
        }

        func integer(_ path: String, min: Int = 0, max: Int = Int.MAX_VALUE, missingDefault: Int = -1) -> Int {
            guard let num = value(path) as? NSNumber,
                  CFGetTypeID(num) != CFBooleanGetTypeID() else {
                unavailable.insert(path)
                return missingDefault
            }
            let d = num.doubleValue
            guard d.isFinite, d == floor(d), d >= Double(min), d <= Double(max) else {
                unavailable.insert(path)
                return missingDefault
            }
            return num.intValue
        }

        func longInt(_ path: String, min: Int64 = 0, max: Int64 = Int64.max) -> Int64 {
            guard let num = value(path) as? NSNumber,
                  CFGetTypeID(num) != CFBooleanGetTypeID() else {
                unavailable.insert(path)
                return -1
            }
            let d = num.doubleValue
            guard d.isFinite, d == floor(d), d >= Double(min), d <= Double(max) else {
                unavailable.insert(path)
                return -1
            }
            return num.int64Value
        }

        func decimal(_ path: String, min: Float = -Float.greatestFiniteMagnitude, max: Float = Float.greatestFiniteMagnitude) -> Float {
            guard let num = value(path) as? NSNumber,
                  CFGetTypeID(num) != CFBooleanGetTypeID() else {
                unavailable.insert(path)
                return .nan
            }
            let f = num.floatValue
            guard f.isFinite, f >= min, f <= max else {
                unavailable.insert(path)
                return .nan
            }
            return f
        }

        func doubleVal(_ path: String, min: Double = -Double.greatestFiniteMagnitude, max: Double = Double.greatestFiniteMagnitude) -> Double {
            guard let num = value(path) as? NSNumber,
                  CFGetTypeID(num) != CFBooleanGetTypeID() else {
                unavailable.insert(path)
                return .nan
            }
            let d = num.doubleValue
            guard d.isFinite, d >= min, d <= max else {
                unavailable.insert(path)
                return .nan
            }
            return d
        }

        func boolean(_ path: String) -> Bool {
            guard let raw = value(path), let b = boolValue(raw) else {
                unavailable.insert(path)
                return false
            }
            return b
        }

        func nullableBoolean(_ path: String) -> Bool? {
            guard let raw = value(path), let b = boolValue(raw) else {
                unavailable.insert(path)
                return nil
            }
            return b
        }

        func optStr(_ dict: [String: Any]?, _ key: String) -> String {
            guard let raw = dict?[key], !(raw is NSNull) else { return "" }
            return String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let driver = {
            let d = decimal("climate.driverTemp", min: 16.0, max: 32.5)
            if d.isFinite {
                unavailable.remove("climate.targetTemp")
                return d
            }
            let alt = decimal("climate.targetTemp", min: 16.0, max: 32.5)
            if alt.isFinite { unavailable.remove("climate.driverTemp") }
            return alt
        }()
        let passenger = decimal("climate.passengerTemp", min: 16.0, max: 32.5)
        let evRange = integer("phev.evRangeKm")
        let fuelRange = integer("phev.fuelRangeKm")
        let explicitTotal = integer("phev.totalRangeKm", min: 0, max: 5000)

        let socParsed: Int = {
            let s = integer("phev.batterySoc", min: 0, max: 100)
            if s >= 0 {
                unavailable.remove("phev.socPercent")
                return s
            }
            let alt = integer("phev.socPercent", min: 0, max: 100)
            if alt >= 0 { unavailable.remove("phev.batterySoc") }
            return alt
        }()

        let fuelPctParsed: Int = {
            let f = integer("phev.fuelLevelPercent", min: 0, max: 100)
            if f >= 0 {
                unavailable.remove("phev.fuelPercent")
                return f
            }
            let alt = integer("phev.fuelPercent", min: 0, max: 100)
            if alt >= 0 { unavailable.remove("phev.fuelLevelPercent") }
            return alt
        }()

        let supported = Set((root["supportedActions"] as? [String]) ?? [])
        let capDict = root["capabilities"] as? [String: Any]
        let camArray = (capDict?["cameraIds"] as? [String]) ?? (root["cameraIds"] as? [String]) ?? []
        let cameras = camArray.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        let windowPaths = ["body.windowfl", "body.windowfr", "body.windowrl", "body.windowrr"]
        let positions = windowPaths.map { integer($0, min: 0, max: 100) }
        let roofPosition = integer("body.sunroofPosition", min: 0, max: 101)
        let trunkOpenValue = nullableBoolean("body.trunkOpen")

        let diagnosticsArray = (root["diagnostics"] as? [[String: Any]]) ?? []
        let diagnosticValues = diagnosticsArray.prefix(32).map { d in
            DiagnosticReading(
                name: d["name"] as? String ?? "",
                propertyId: d["propertyId"] as? String ?? "",
                area: CommandProtocol.jsonInt(d["area"]) ?? 0,
                value: (d["value"] is NSNull || d["value"] == nil) ? nil : String(describing: d["value"]!)
            )
        }

        let engineSoundObj = root["engineSound"] as? [String: Any]
        let lightShowObj = root["lightShow"] as? [String: Any]
        let phevObj = root["phev"] as? [String: Any]
        let airQualityObj = root["airQuality"] as? [String: Any]
        let deepDiagObj = root["deepDiagnostics"] as? [String: Any]
        let sensorsObj = root["sensors"] as? [String: Any]
        let connObj = root["connection"] as? [String: Any]
        let systemObj = root["system"] as? [String: Any]
        let agentSetObj = root["agentSettings"] as? [String: Any]
        let secObj = root["security"] as? [String: Any]
        let ignObj = root["ignition"] as? [String: Any]
        let tiresObj = root["tires"] as? [String: Any]
        let locObj = root["location"] as? [String: Any]

        let rawDiagArr = (deepDiagObj?["rawSensors"] as? [[String: Any]]) ?? []
        let rawDiagList = rawDiagArr.prefix(48).map { d in
            DiagnosticReading(
                name: d["name"] as? String ?? "",
                propertyId: d["propertyId"] as? String ?? "",
                area: CommandProtocol.jsonInt(d["area"]) ?? 0,
                value: (d["value"] is NSNull || d["value"] == nil) ? nil : String(describing: d["value"]!)
            )
        }

        var dtcList: [DtcFaultItem] = []
        for item in (deepDiagObj?["dtcCodes"] as? [[String: Any]]) ?? [] {
            let entry = DtcFaultItem(
                code: item["code"] as? String ?? "P0000",
                system: item["system"] as? String ?? "ECU",
                severity: item["severity"] as? String ?? "INFO",
                description: item["description"] as? String ?? ""
            )
            if entry.severity.uppercased() == "WARNING" || entry.code.hasPrefix("WARN_") {
                // split below
            } else {
                dtcList.append(entry)
            }
        }
        var panelWarnList: [DtcFaultItem] = []
        for item in (deepDiagObj?["dtcCodes"] as? [[String: Any]]) ?? [] {
            let code = item["code"] as? String ?? "P0000"
            let sev = item["severity"] as? String ?? "INFO"
            if sev.uppercased() == "WARNING" || code.hasPrefix("WARN_") {
                panelWarnList.append(DtcFaultItem(
                    code: code,
                    system: item["system"] as? String ?? "PANEL",
                    severity: sev,
                    description: item["description"] as? String ?? ""
                ))
            }
        }
        for item in (deepDiagObj?["panelWarnings"] as? [[String: Any]]) ?? [] {
            panelWarnList.append(DtcFaultItem(
                code: item["code"] as? String ?? "WARN",
                system: item["system"] as? String ?? "PANEL",
                severity: item["severity"] as? String ?? "WARNING",
                description: item["description"] as? String ?? ""
            ))
        }
        let ecuModules = ((deepDiagObj?["ecuModules"] as? [[String: Any]]) ?? []).map {
            EcuModuleItem(
                code: $0["code"] as? String ?? "ECU",
                name: $0["name"] as? String ?? "",
                status: $0["status"] as? String ?? "OK"
            )
        }

        var state = TelemetryState()
        state.energyMode = optStr(connObj, "energyMode")
        state.standbyKeepalive = boolValue(root["standbyKeepalive"]) ?? boolValue(connObj?["standbyKeepalive"]) ?? false
        state.diagnostics = rawDiagList.isEmpty ? diagnosticValues : rawDiagList
        state.ventilationStatus = optStr(connObj, "ventilation")
        state.vin = exp.isEmpty ? packetVin : exp
        state.lastUpdateEpoch = (root["timestamp"] as? NSNumber)?.int64Value ?? 0
        state.ignitionState = integer("ignition.state", min: 0, max: 10)
        state.ignitionDescription = optStr(ignObj, "description").isEmpty ? "Məlumat yoxdur" : optStr(ignObj, "description")
        state.isCabinReady = boolean("ignition.isCabinReady")
        state.batterySoc = socParsed
        state.evRangeKm = evRange
        state.fuelRangeKm = fuelRange
        state.totalRangeKm = explicitTotal >= 0 ? explicitTotal : (evRange >= 0 && fuelRange >= 0 ? evRange + fuelRange : -1)
        state.isCharging = boolean("phev.isCharging")
        state.climatePower = boolean("climate.power")
        state.targetTemp = driver
        state.driverTemp = driver
        state.passengerTemp = passenger
        state.fanSpeed = integer("climate.fanSpeed", min: 0, max: 8)
        state.windMode = integer("climate.windMode", min: 0, max: 10)
        state.acCompressor = boolean("climate.acCompressor")
        state.maxAc = boolean("climate.maxAc")
        state.autoMode = boolean("climate.autoMode")
        state.defrost = boolean("climate.defrost")
        state.rearDefrost = boolean("climate.rearDefrost")
        state.recirculation = boolean("climate.recirculation")
        state.airPurifier = boolean("climate.airPurifier")
        state.autoDefog = boolean("climate.autoDefog")
        state.airDry = boolean("climate.airDry")
        state.naturalWind = boolean("climate.naturalWind")
        state.ecoClimate = boolean("climate.ecoMode")
        state.smokeMode = boolean("climate.smokeMode")

        state.wiperServiceMode = boolean("body.wiperServiceMode")
        state.doorsLocked = boolean("body.doorsLocked")
        if positions.allSatisfy({ $0 >= 0 }) {
            unavailable.remove("body.windowsClosed")
            state.windowsClosed = positions.allSatisfy { $0 == 0 }
        } else {
            unavailable.insert("body.windowsClosed")
        }
        if roofPosition >= 0 {
            unavailable.remove("body.sunroofClosed")
            state.sunroofClosed = roofPosition == 0
        } else {
            unavailable.insert("body.sunroofClosed")
        }
        if let trunkOpenVal = trunkOpenValue {
            unavailable.remove("body.trunkClosed")
            state.trunkClosed = !trunkOpenVal
        } else {
            unavailable.insert("body.trunkClosed")
        }
        state.doorFlOpen = boolean("body.doorFlOpen")
        state.doorFrOpen = boolean("body.doorFrOpen")
        state.doorRlOpen = boolean("body.doorRlOpen")
        state.doorRrOpen = boolean("body.doorRrOpen")
        state.hoodOpen = boolean("body.hoodOpen")
        state.trunkOpen = trunkOpenValue ?? false
        state.fuelDoorOpen = nullableBoolean("body.fuelDoorOpen")

        func parsePressure(_ path: String) -> Float {
            let p = decimal(path, min: 0, max: 10)
            return (p.isFinite && p >= 0.5) ? p : .nan
        }
        state.tirePressureFl = parsePressure("tires.pressureFl")
        state.tirePressureFr = parsePressure("tires.pressureFr")
        state.tirePressureRl = parsePressure("tires.pressureRl")
        state.tirePressureRr = parsePressure("tires.pressureRr")

        func parseTireStatus(_ strKey: String, _ statePath: String) -> String {
            let explicit = optStr(tiresObj, strKey)
            if !explicit.isEmpty { return explicit }
            let code = integer(statePath, min: 0, max: 9)
            if code == 0 { return "OK" }
            if (1...9).contains(code) { return "LOW" }
            return ""
        }
        state.tireStatusFl = parseTireStatus("statusFl", "tires.stateFl")
        state.tireStatusFr = parseTireStatus("statusFr", "tires.stateFr")
        state.tireStatusRl = parseTireStatus("statusRl", "tires.stateRl")
        state.tireStatusRr = parseTireStatus("statusRr", "tires.stateRr")
        state.tpmsMode = optStr(tiresObj, "tpmsMode")
        state.tireTempFl = integer("tires.tempFl", min: -50, max: 150, missingDefault: -1000)
        state.tireTempFr = integer("tires.tempFr", min: -50, max: 150, missingDefault: -1000)
        state.tireTempRl = integer("tires.tempRl", min: -50, max: 150, missingDefault: -1000)
        state.tireTempRr = integer("tires.tempRr", min: -50, max: 150, missingDefault: -1000)

        state.fuelPercent = fuelPctParsed
        state.cameraIds = cameras
        state.latitude = doubleVal("location.latitude", min: -90, max: 90)
        state.longitude = doubleVal("location.longitude", min: -180, max: 180)
        state.locationEpoch = (locObj?["timestamp"] as? NSNumber)?.int64Value ?? 0
        state.locationAccuracy = decimal("location.accuracy")
        state.windowPositions = positions
        state.sunroofPosition = roofPosition
        state.supportedActions = supported
        state.outsideTemp = decimal("sensors.outsideTemp", min: -60, max: 90)
        state.cabinTemp = decimal("sensors.cabinTemp", min: -50, max: 90)
        state.vehicleSpeed = decimal("sensors.speedKmH", min: 0, max: 350)
        state.odometerKm = decimal("sensors.odometerKm", min: 0, max: 2_000_000)
        state.gear = optStr(sensorsObj, "gear")
        state.parkingBrake = nullableBoolean("sensors.parkingBrake")

        let b12 = decimal("sensors.battery12V", min: 0, max: 25)
        if b12.isFinite {
            unavailable.remove("deepDiagnostics.battery12vVolts")
            state.batteryVoltage12V = b12
        } else {
            let alt12 = decimal("deepDiagnostics.battery12vVolts", min: 0, max: 25)
            if alt12.isFinite { unavailable.remove("sensors.battery12V") }
            state.batteryVoltage12V = alt12
        }

        state.engineSoundEnabled = boolValue(engineSoundObj?["enabled"]) ?? false
        state.engineSoundProfile = optStr(engineSoundObj, "profile").isEmpty ? "BMW_M_V8" : optStr(engineSoundObj, "profile")
        state.engineSoundVolume = optStr(engineSoundObj, "volume").isEmpty ? "normal" : optStr(engineSoundObj, "volume")
        state.virtualRpm = CommandProtocol.jsonInt(engineSoundObj?["virtualRpm"]) ?? 0
        if sensorsObj?["throttlePercent"] != nil && !(sensorsObj?["throttlePercent"] is NSNull) {
            state.throttlePercent = integer("sensors.throttlePercent", min: 0, max: 100)
        } else if deepDiagObj?["throttlePercent"] != nil && !(deepDiagObj?["throttlePercent"] is NSNull) {
            state.throttlePercent = integer("deepDiagnostics.throttlePercent", min: 0, max: 100)
        } else if engineSoundObj?["throttlePercent"] != nil && !(engineSoundObj?["throttlePercent"] is NSNull) {
            state.throttlePercent = integer("engineSound.throttlePercent", min: 0, max: 100)
        }

        state.lightShowActive = boolValue(lightShowObj?["active"]) ?? false
        let lsProfile = optStr(lightShowObj, "profile")
        state.lightShowProfile = (lsProfile.isEmpty || lsProfile == "null") ? "BEAT_SYNC" : lsProfile
        let lsRoute = optStr(lightShowObj, "route")
        state.lightShowRoute = (lsRoute.isEmpty || lsRoute == "null") ? "DUAL" : lsRoute
        let lsTrack = optStr(lightShowObj, "track")
        state.lightShowTrack = (lsTrack.isEmpty || lsTrack == "null") ? "user_hero" : lsTrack
        state.lightShowHeadlights = boolValue(lightShowObj?["headlights"]) ?? true
        state.lightShowHighBeams = boolValue(lightShowObj?["highBeams"]) ?? true
        state.lightShowTurnSignals = boolValue(lightShowObj?["turnSignals"]) ?? true
        state.lightShowWidthLamps = boolValue(lightShowObj?["widthLamps"]) ?? true
        state.lightShowVentWindows = boolValue(lightShowObj?["ventWindows"]) ?? false
        state.lightShowBcmGate = CommandProtocol.jsonInt(lightShowObj?["bcmGateStatus"]) ?? -1
        state.lightShowDirectFallback = boolValue(lightShowObj?["directFallbackActive"]) ?? false

        state.batterySoh = decimal("phev.sohPercent", min: 0, max: 150)
        state.hvVoltage = decimal("phev.hvVoltage", min: 0, max: 1000)
        state.hvCurrent = decimal("phev.hvCurrent", min: -1000, max: 1000)
        state.hvPowerKw = decimal("phev.hvPowerKw", min: -500, max: 500)
        state.regenPowerKw = decimal("phev.regenPowerKw", min: 0, max: 500)
        state.cellMinMv = integer("phev.cellMinMv", min: 0, max: 6000)
        state.cellMaxMv = integer("phev.cellMaxMv", min: 0, max: 6000)
        state.cellDeltaMv = integer("phev.cellDeltaMv", min: 0, max: 6000)
        state.batteryTempMin = decimal("phev.tempMinC", min: -60, max: 120)
        state.batteryTempMax = decimal("phev.tempMaxC", min: -60, max: 120)
        state.chargeCycles = integer("phev.chargeCycles", min: 0, max: 100_000)
        state.packCapacityKwh = (phevObj?["packCapacityKwh"] as? NSNumber)?.floatValue ?? 18.99
        let chem = optStr(phevObj, "chemistry")
        if !chem.isEmpty { state.batteryChemistry = chem }
        state.isRatedSpec = boolValue(phevObj?["isRatedSpec"]) ?? true
        state.saveTargetSoc = integer("phev.saveTargetSoc", min: 0, max: 100)
        state.chargeMaxSoc = integer("phev.chargeMaxSoc", min: 0, max: 100)
        state.fuelLevelLow = nullableBoolean("phev.fuelLevelLow")
        state.saveFuelLitres = decimal("phev.saveFuelLitres", min: 0, max: 200)
        state.chargePortOpen = nullableBoolean("phev.chargePortOpen")
        state.chargePortConnected = nullableBoolean("phev.chargePortConnected")
        state.chargeRateKw = decimal("phev.chargeRateKw", min: -200, max: 300)
        state.energyFlowMode = integer("phev.energyFlowMode", min: 0, max: 99)
        state.chargeDisMode = integer("phev.chargeDisMode", min: 0, max: 99)

        state.pm25Inside = CommandProtocol.jsonInt(airQualityObj?["pm25Inside"]) ?? -1
        state.pm25Outside = CommandProtocol.jsonInt(airQualityObj?["pm25Outside"]) ?? -1
        state.airQualityLevel = optStr(airQualityObj, "level")
        let parsedAqs = boolValue(airQualityObj?["aqsEnabled"])
        if parsedAqs == nil { unavailable.insert("airQuality.aqsEnabled") }
        state.aqsEnabled = parsedAqs ?? false
        state.aqsState = parsedAqs

        let parsedIon = boolValue(airQualityObj?["ionizerEnabled"]) ?? boolValue((root["climate"] as? [String: Any])?["airPurifier"])
        if parsedIon == nil { unavailable.insert("airQuality.ionizerEnabled") }
        state.ionizerEnabled = parsedIon ?? false
        state.ionizerState = boolValue(airQualityObj?["ionizerEnabled"])

        let cool = decimal("sensors.coolantTemp", min: -60, max: 220)
        if cool.isFinite {
            unavailable.remove("deepDiagnostics.coolantTempC")
            state.coolantTempC = cool
        } else {
            let alt = decimal("deepDiagnostics.coolantTempC", min: -60, max: 220)
            if alt.isFinite { unavailable.remove("sensors.coolantTemp") }
            state.coolantTempC = alt
        }
        let oilT = decimal("deepDiagnostics.oilTempC", min: -60, max: 250)
        if oilT.isFinite {
            unavailable.remove("sensors.oilTemp")
            state.oilTempC = oilT
        } else {
            let alt = decimal("sensors.oilTemp", min: -60, max: 250)
            if alt.isFinite { unavailable.remove("deepDiagnostics.oilTempC") }
            state.oilTempC = alt
        }
        state.oilPressureStatus = optStr(deepDiagObj, "oilPressureStatus").isEmpty ? optStr(sensorsObj, "oilPressureStatus") : optStr(deepDiagObj, "oilPressureStatus")
        let oilRaw = integer("sensors.oilInfoRaw", min: 0, max: 255)
        state.oilInfoRaw = oilRaw >= 0 ? oilRaw : integer("deepDiagnostics.oilInfoRaw", min: 0, max: 255)
        state.inverterTempC = decimal("deepDiagnostics.inverterTempC", min: -60, max: 250)
        state.motorTempC = decimal("deepDiagnostics.motorTempC", min: -60, max: 250)
        state.engineRpm = integer("sensors.engineRpm", min: 0, max: 15000)
        state.dtcCodes = dtcList
        state.panelWarnings = panelWarnList
        state.ecuModules = ecuModules
        state.warningChannelsCount = integer("deepDiagnostics.warningChannelsCount", min: 0, max: 200)
        state.faultChannelsCount = integer("deepDiagnostics.faultChannelsCount", min: 0, max: 200)

        state.headlightsOn = boolean("lights.headlights")
        state.selektorOn = boolean("lights.selektor")
        state.decorativeLightOn = boolean("lights.decorativeLight")
        state.fogLightsOn = boolean("lights.fogLights")
        state.domeLightOn = boolean("lights.domeLight")
        state.ambientLightOn = boolean("lights.ambientLight")
        let ambBri = integer("lights.ambientBrightness", min: 0, max: 6)
        state.ambientBrightness = ambBri >= 0 ? ambBri : 5
        let ambCol = integer("lights.ambientColor", min: 1, max: 64)
        state.ambientColor = ambCol >= 1 ? ambCol : 1
        state.driveMode = optStr(sensorsObj, "driveMode").isEmpty ? "NORMAL" : optStr(sensorsObj, "driveMode")
        state.driveSubMode = optStr(sensorsObj, "driveSubMode")
        state.safetyArmed = boolValue(secObj?["safetyArmed"]) ?? false
        state.safetyAlarmTriggered = boolValue(secObj?["alarmTriggered"]) ?? false

        state.autoHold = nullableBoolean("sensors.autoHold")
        state.absActive = nullableBoolean("sensors.absActive")
        state.tcsActive = nullableBoolean("sensors.tcsActive")
        state.steeringAngleRaw = decimal("sensors.steeringAngleRaw", min: -32768, max: 32768)
        state.fuelConsumptionAvg = decimal("sensors.fuelConsumptionAvg", min: 0, max: 100)
        state.nightMode = nullableBoolean("sensors.nightMode")
        state.rainLevel = integer("sensors.rainLevel", min: 0, max: 255)
        state.wirelessCharging = nullableBoolean("sensors.wirelessCharging")
        state.sunshadePosition = integer("body.sunshadePosition", min: 0, max: 100)
        state.seatbeltDriverRaw = integer("body.seatbeltDriverRaw", min: 0, max: 99)
        state.seatbeltPassengerRaw = integer("body.seatbeltPassengerRaw", min: 0, max: 99)
        state.seatbeltRlRaw = integer("body.seatbeltRlRaw", min: 0, max: 99)
        state.seatbeltRcRaw = integer("body.seatbeltRcRaw", min: 0, max: 99)
        state.seatbeltRrRaw = integer("body.seatbeltRrRaw", min: 0, max: 99)
        state.dvrStoragePercent = integer("dvr.storagePercent", min: 0, max: 100)
        state.dvrSdError = nullableBoolean("dvr.sdError")
        state.dvrSdFull = nullableBoolean("dvr.sdFull")

        state.gpsEnabled = nullableBoolean("location.gpsEnabled")
        state.altitudeM = doubleVal("location.altitudeM", min: -1000, max: 20000)
        state.gpsSpeedKmh = decimal("location.speedKmh", min: 0, max: 400)
        state.bearingDeg = decimal("location.bearingDeg", min: 0, max: 360)
        state.gpsSatellites = integer("location.satellites", min: 0, max: 200)
        state.agentVersion = optStr(systemObj, "agentVersion")
        state.androidVersion = optStr(systemObj, "androidVersion")
        state.deviceModel = optStr(systemObj, "deviceModel")
        state.uptimeSec = longInt("system.uptimeSec", min: 0, max: 100_000_000)
        state.ramFreeMb = integer("system.ramFreeMb", min: 0, max: 262_144)
        state.ramTotalMb = integer("system.ramTotalMb", min: 0, max: 262_144)
        state.storageFreeMb = integer("system.storageFreeMb", min: 0, max: 10_000_000)
        state.storageTotalMb = integer("system.storageTotalMb", min: 0, max: 10_000_000)
        state.networkTransport = optStr(systemObj, "networkTransport")
        state.wifiEnabled = nullableBoolean("system.wifiEnabled")
        state.wifiSsid = optStr(systemObj, "wifiSsid")
        if let rssi = CommandProtocol.jsonInt(systemObj?["wifiRssiDbm"]), (-126 ... -1).contains(rssi) {
            state.wifiRssiDbm = rssi
        }
        state.wifiIp = optStr(systemObj, "wifiIp")
        state.bluetoothEnabled = nullableBoolean("system.bluetoothEnabled")
        state.mcuVersion = optStr(systemObj, "mcuVersion")
        state.dspVersion = optStr(systemObj, "dspVersion")
        state.hwVersion = optStr(systemObj, "hwVersion")
        state.tboxIccid = optStr(systemObj, "tboxIccid")
        state.oemConnected = boolValue(connObj?["oemConnected"])

        state.agentAutoMuteAvas = boolValue(agentSetObj?["autoMuteAvas"])
        state.agentLockChimeEnabled = boolValue(agentSetObj?["lockChimeEnabled"])
        state.agentLockVolumePct = CommandProtocol.jsonInt(agentSetObj?["lockVolumePercent"]) ?? -1
        state.agentSirenVolumePct = CommandProtocol.jsonInt(agentSetObj?["sirenVolumePercent"]) ?? -1
        state.agentEngineVolumePct = CommandProtocol.jsonInt(agentSetObj?["engineVolumePercent"]) ?? -1
        state.agentMegaphoneVolumePct = CommandProtocol.jsonInt(agentSetObj?["megaphoneVolumePercent"]) ?? -1
        state.agentLsAvasVolumePct = CommandProtocol.jsonInt(agentSetObj?["lsAvasVolumePercent"]) ?? -1
        state.agentLsCabinVolumePct = CommandProtocol.jsonInt(agentSetObj?["lsCabinVolumePercent"]) ?? -1
        state.agentRadioRecovery = boolValue(agentSetObj?["radioRecovery"])
        state.agentAutoClimate = boolValue(agentSetObj?["autoClimate"])
        state.agentVehiclePlate = optStr(agentSetObj, "vehiclePlate")

        state.unavailableFields = unavailable
        return state
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        guard let num = raw as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() else {
            return raw as? Bool
        }
        return num.boolValue
    }
}
