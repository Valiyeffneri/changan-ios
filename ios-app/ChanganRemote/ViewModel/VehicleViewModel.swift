import Foundation
import SwiftUI
import UIKit
import Photos
import Combine

@MainActor
final class VehicleViewModel: ObservableObject {
    // MARK: - Persistent Config & Registration
    @Published var brokerUrl: String
    @Published var vin: String
    @Published var secretKey: String
    @Published var allowInsecureCustomTls: Bool

    @Published var userFirstName: String
    @Published var userLastName: String
    @Published var carBrand: String
    @Published var carModel: String
    @Published var carYear: String
    @Published var carColor: String
    @Published var carPlate: String
    @Published var isRegistered: Bool
    @Published var isVehiclePaired: Bool

    // MARK: - Live Telemetry & UI State
    @Published var telemetry: TelemetryState
    @Published var connectionUiState = ConnectionUiState()
    @Published var commandBanner: CommandBannerState?
    @Published var pendingCommandCount: Int = 0
    @Published var toastMessage: String?
    @Published var wiperServiceActive: Bool = false
    @Published var parkChargeStarting: Bool = false
    @Published var rapidVentRemainingSeconds: Int? = nil

    // MARK: - Camera & Audio State
    @Published var cameraImage: UIImage?
    @Published var cameraTimestampMs: Int64 = 0
    @Published var isCameraLoading: Bool = false
    @Published var isVideoStreaming: Bool = false
    @Published var isH264VideoActive: Bool = false
    @Published var videoAspectRatio: CGFloat = 4.0 / 3.0
    @Published var videoWidth: Int = 640
    @Published var videoHeight: Int = 480
    @Published var videoFps: Int = 0
    @Published var videoBitrateKbps: Int = 0

    @Published var isCabinListening: Bool = false
    @Published var isTalking: Bool = false
    @Published var avasVolumeTier: String
    @Published var avasVolume: Float

    // MARK: - Confirmation Dialog State
    struct ControlConfirmation: Identifiable {
        let id = UUID()
        let action: String
        let title: String
        let message: String
        let params: [String: Any]
        let expiresAt: Date
    }
    @Published var controlConfirmation: ControlConfirmation?

    let h264Decoder = H264VideoDecoder()
    let audioManager = CabinAudioManager()

    private let defaults = UserDefaults.standard
    private var mqttClient: MqttClient!
    private let optimisticRegistry = OptimisticStateRegistry(defaultHoldSeconds: 5.0)
    private var lastConfirmedTelemetry: TelemetryState

    private var cloudConnected = false
    private var agentPresenceOnline = false
    private var lastOnlineAt: Date?
    private var cloudLatencyMs: Int64?
    private var manualCloudDisabled = false
    private var lastTrulyOnline = false
    private var syncTemperatures = true
    private var lastAutoSyncedPlate = ""
    private var plateSyncInFlight: String?

    private struct PendingCommand {
        let action: String
        let timeoutTask: Task<Void, Never>
        let silent: Bool
        let sentAt: Date
        let optimisticKeys: Set<String>
    }
    private var pending: [String: PendingCommand] = [:]
    private var ackWaiters: [String: CheckedContinuation<(Bool, String), Never>] = [:]
    private var mediaRequests: [String: Date] = [:]
    private var pendingAutoSaveSnapshotIds: [String: (deadline: Date, fallback: UIImage?)] = [:]

    private var bannerSeq: Int64 = 0
    private var bannerDismissTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var ventilationTask: Task<Void, Never>?
    private var revResetTask: Task<Void, Never>?
    private var parkChargeTask: Task<Void, Never>?
    private var liveVideoKeepaliveTask: Task<Void, Never>?
    private var cabinListenKeepaliveTask: Task<Void, Never>?

    private var activeVideoId: String?
    private var lastVideoSequence = 0
    private var activeCabinAudioId: String?
    private var lastAudioSequence = 0
    private var talkStartId: String?
    private var talkReadyWaiter: CheckedContinuation<(Bool, String), Never>?
    private var currentLiveSession: String?
    private var talkSeq = 0

    private var fpsWindowStart: Date?
    private var fpsFrameCount = 0
    private var lastSilentPingAt: Date = .distantPast
    private var lastSilentRefreshAt: Date = .distantPast

    private let mediaActions: Set<String> = ["CAPTURE_CAMERA", "START_CAMERA_STREAM", "RECORD_AUDIO", "START_CABIN_AUDIO_STREAM"]
    private let alwaysAllowedActions: Set<String> = [
        "PLAY_AVAS_SOUND", "STOP_AVAS_SOUND", "AVAS_TALK",
        "START_CAMERA_STREAM", "STOP_CAMERA_STREAM", "CAMERA_SWITCH",
        "START_CABIN_AUDIO_STREAM", "STOP_CABIN_AUDIO_STREAM", "CABIN_AUDIO_KEEPALIVE",
        "REMOTE_START", "REMOTE_STOP", "SET_STANDBY_MODE",
        "SET_ENGINE_SOUND", "REV_ENGINE_SOUND",
        "CLEAR_DTC", "RUN_FULL_DIAGNOSTICS",
        "LOCK_DOORS", "UNLOCK_DOORS", "OPEN_TRUNK", "OPEN_FUEL_CAP",
        "SET_SUNROOF_POS", "TILT_SUNROOF",
        "SET_WINDOW_POS", "OPEN_WINDOWS", "CLOSE_WINDOWS", "VENT_WINDOWS", "SET_ALL_WINDOWS",
        "VENT_CABIN", "STOP_VENT_CABIN",
        "SET_LIGHTS", "SET_WIPER", "SET_DRIVE_MODE", "SET_SAFETY_MODE",
        "START_LIGHT_SHOW", "STOP_LIGHT_SHOW",
        "SET_AGENT_SETTINGS", "PAIR_CONFIRM"
    ]

    init() {
        let savedBroker = defaults.string(forKey: "broker_url")
        let initialBroker = (savedBroker?.isEmpty == false && savedBroker != "tcp://broker.hivemq.com:1883")
            ? savedBroker! : CommandProtocol.defaultBrokerUrl
        let savedVin = defaults.string(forKey: "vin") ?? ""
        let cleanVin = (savedVin == "----" || savedVin.hasPrefix("5L8ANE0Z68A")) ? "" : savedVin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
        let savedSecret = defaults.string(forKey: "secret_key")
        let initialSecret = (savedSecret?.isEmpty == false) ? savedSecret! : CommandProtocol.defaultSharedSecret

        self.brokerUrl = initialBroker
        self.vin = cleanVin
        self.secretKey = initialSecret
        self.allowInsecureCustomTls = defaults.bool(forKey: "allow_insecure_custom_tls")

        self.userFirstName = defaults.string(forKey: "user_first_name") ?? ""
        self.userLastName = defaults.string(forKey: "user_last_name") ?? ""
        self.carBrand = defaults.string(forKey: "car_brand") ?? "Changan"
        self.carModel = defaults.string(forKey: "car_model") ?? ""
        self.carYear = defaults.string(forKey: "car_year") ?? ""
        self.carColor = defaults.string(forKey: "car_color") ?? ""
        self.carPlate = defaults.string(forKey: "car_plate") ?? ""
        self.isRegistered = defaults.bool(forKey: "is_registered")
        self.isVehiclePaired = defaults.bool(forKey: "is_vehicle_paired")

        let tier = defaults.string(forKey: "avas_volume_tier") ?? "strong"
        self.avasVolumeTier = tier
        let storedVol = defaults.object(forKey: "avas_volume") as? Float
        self.avasVolume = storedVol ?? (tier == "weak" ? 0.4 : (tier == "normal" ? 1.0 : 2.5))

        let baseTelemetry = TelemetryState(vin: cleanVin)
        self.telemetry = baseTelemetry
        self.lastConfirmedTelemetry = baseTelemetry

        self.mqttClient = MqttClient(brokerUrl: initialBroker, vin: cleanVin, secretKey: initialSecret)
        self.mqttClient.allowInsecureCustomTls = self.allowInsecureCustomTls

        self.mqttClient.onStateChanged = { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cloudConnected = (newState == .connected)
                self.updateConnectivity()
            }
        }
        self.mqttClient.onTelemetryReceived = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.receiveTelemetry(state)
            }
        }
        self.mqttClient.onPresenceChanged = { [weak self] online, ts in
            Task { @MainActor [weak self] in
                self?.handlePresenceChanged(online: online, timestampSec: ts)
            }
        }
        self.mqttClient.onAckReceived = { [weak self] ack in
            Task { @MainActor [weak self] in
                self?.handleAck(ack)
            }
        }
        self.mqttClient.onMediaReceived = { [weak self] json in
            Task { @MainActor [weak self] in
                self?.handleMediaPacket(json)
            }
        }
        self.mqttClient.onTransportStatus = { [weak self] id, status, _ in
            Task { @MainActor [weak self] in
                guard let self, self.pending[id] != nil else { return }
                if status == "EXPIRED" || status == "CANCELLED" || status == "FAILED" {
                    self.finishCommand(id, text: "Avtomobillə əlaqə yoxdur", isError: true)
                }
            }
        }

        if !cleanVin.isEmpty {
            self.mqttClient.connect()
        }

        self.tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { break }
                self.updateConnectivity()
                self.maybeSendKeepalivePing()
                let now = Date()
                self.mediaRequests = self.mediaRequests.filter { $0.value > now }
                self.pendingAutoSaveSnapshotIds = self.pendingAutoSaveSnapshotIds.filter { $0.value.deadline > now }
            }
        }
    }

    deinit {
        tickerTask?.cancel()
        mqttClient.disconnect()
    }

    // MARK: - Registration & Pairing

    func saveRegistration(
        firstName: String,
        lastName: String,
        model: String,
        year: String,
        vinInput: String,
        color: String,
        plate: String
    ) -> Bool {
        let cleanFirst = firstName.split(separator: " ").map { $0.lowercased().capitalized }.joined(separator: " ")
        let cleanLast = lastName.split(separator: " ").map { $0.lowercased().capitalized }.joined(separator: " ")
        let cleanVin = vinInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "Q", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .filter { $0.isLetter || $0.isNumber }

        let rawPlate = plate.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
        let cleanPlate: String
        if !rawPlate.contains("-"), rawPlate.count == 7 {
            let p1 = rawPlate.prefix(2)
            let p2 = rawPlate.dropFirst(2).prefix(2)
            let p3 = rawPlate.suffix(3)
            cleanPlate = "\(p1)-\(p2)-\(p3)"
        } else {
            cleanPlate = rawPlate
        }

        let cleanColor = (color == "Ağ") ? "Ağ" : "Yaş asfalt"
        let cleanModel = (model == "Qiyuan A05") ? "Qiyuan A05" : "EADO PHEV"
        let cleanYear = (year == "2024") ? "2024" : "2025"

        guard !cleanFirst.isEmpty, !cleanLast.isEmpty else {
            toastMessage = "Zəhmət olmasa ad və soyad daxil edin"
            return false
        }
        guard cleanVin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            toastMessage = "VİN kodu 17 simvollu beynəlxalq standart formatda olmalıdır."
            return false
        }
        let alreadyRegistered = defaults.bool(forKey: "is_registered")
        let existingVin = defaults.string(forKey: "vin") ?? ""
        if alreadyRegistered && !existingVin.isEmpty && existingVin != cleanVin {
            toastMessage = "Təhlükəsizlik qaydası: 1 proqram nüsxəsi yalnız 1 VİN kod üçün qeydiyyatdan keçə bilər."
            return false
        }
        guard cleanPlate.range(of: "^\\d{2}-[A-Z]{2}-\\d{3}$", options: .regularExpression) != nil else {
            toastMessage = "Dövlət qeydiyyat nişanı düzgün daxil edilməlidir (Format: XX-YY-ZZZ)"
            return false
        }

        defaults.set(cleanFirst, forKey: "user_first_name")
        defaults.set(cleanLast, forKey: "user_last_name")
        defaults.set("Changan", forKey: "car_brand")
        defaults.set(cleanModel, forKey: "car_model")
        defaults.set(cleanYear, forKey: "car_year")
        defaults.set(cleanColor, forKey: "car_color")
        defaults.set(cleanPlate, forKey: "car_plate")
        defaults.set(cleanVin, forKey: "vin")
        defaults.set(true, forKey: "is_registered")

        userFirstName = cleanFirst
        userLastName = cleanLast
        carBrand = "Changan"
        carModel = cleanModel
        carYear = cleanYear
        carColor = cleanColor
        carPlate = cleanPlate
        isRegistered = true

        _ = updateSettings(newBroker: brokerUrl, newVin: cleanVin, newSecret: secretKey)
        lastAutoSyncedPlate = ""
        if cloudConnected {
            lastAutoSyncedPlate = cleanPlate
            setAgentSettings(["vehiclePlate": cleanPlate])
        }
        toastMessage = "Qeydiyyat uğurla tamamlandı!"
        return true
    }

    func completeVehiclePairing(pin: String, completion: @escaping (Bool, String?) -> Void) {
        let cleanPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPin.count == 6, cleanPin.allSatisfy(\.isNumber), cleanPin != "000000" else {
            let msg = "Etibarlı 6-rəqəmli təhlükəsizlik PİN kodu daxil edin (000000 qəbul edilmir)"
            toastMessage = msg
            completion(false, msg)
            return
        }
        guard vin.count == 17 else {
            let msg = "Əvvəlcə avtomobilin 17-simvollu VİN kodunu daxil edin və ya QR skan edin"
            toastMessage = msg
            completion(false, msg)
            return
        }
        verifyPairConfirmWithAgent(pinCode: cleanPin, completion: completion)
    }

    func completeVehiclePairingWithQr(_ qrData: String, completion: @escaping (Bool, String?) -> Void) {
        let fields = parseQrRegistrationFields(qrData)
        let qrVin = fields["vin"] ?? ""
        let qrSecret = fields["sec"] ?? ""
        let qrCode = fields["code"] ?? ""
        let qrBroker = fields["broker"] ?? ""
        let qrPlate = fields["plate"] ?? ""

        guard qrCode.count == 6, qrCode.allSatisfy(\.isNumber), qrCode != "000000" else {
            let msg = "QR kodda etibarlı 6-rəqəmli təsdiq kodu yoxdur"
            toastMessage = msg
            completion(false, msg)
            return
        }
        guard qrSecret.count >= 16 else {
            let msg = "QR kodda təhlükəsizlik açarı (HMAC) natamamdır"
            toastMessage = msg
            completion(false, msg)
            return
        }
        guard qrVin.count == 17 else {
            let msg = "QR kodda 17-simvollu VİN tapılmadı"
            toastMessage = msg
            completion(false, msg)
            return
        }

        let prevVin = vin
        let prevBroker = brokerUrl
        let prevSecret = secretKey
        let prevPlate = carPlate

        let curVinClean = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
        if curVinClean.count == 17 && curVinClean != "QA_OFFLINE_NO_VEHICLE" && qrVin != curVinClean {
            let msg = "Skan edilmiş QR kod qeydiyyatda olan VİN ilə uyğun gəlmir (\(qrVin) ≠ \(curVinClean))"
            toastMessage = msg
            completion(false, msg)
            return
        }
        vin = qrVin
        if !qrBroker.isEmpty {
            guard isValidBrokerUri(qrBroker) else {
                vin = prevVin
                let msg = "QR kodda broker ünvanı etibarsızdır"
                toastMessage = msg
                completion(false, msg)
                return
            }
            brokerUrl = qrBroker
        }
        secretKey = qrSecret

        let applyQrPlate = (qrPlate.range(of: "^\\d{2}-[A-Z]{2}-\\d{3}$", options: .regularExpression) != nil)
            || (!qrPlate.isEmpty && prevPlate.isEmpty)
        if applyQrPlate {
            carPlate = qrPlate
        }

        mqttClient.updateConfig(brokerUrl: brokerUrl, vin: vin, secretKey: secretKey)
        verifyPairConfirmWithAgent(
            pinCode: qrCode,
            onSuccessCommit: {
                self.defaults.set(self.vin, forKey: "vin")
                self.defaults.set(self.brokerUrl, forKey: "broker_url")
                self.defaults.set(self.secretKey, forKey: "secret_key")
                if applyQrPlate { self.defaults.set(qrPlate, forKey: "car_plate") }
            },
            onFailureRollback: {
                self.vin = prevVin
                self.brokerUrl = prevBroker
                self.secretKey = prevSecret
                self.carPlate = prevPlate
                self.mqttClient.updateConfig(brokerUrl: prevBroker, vin: prevVin, secretKey: prevSecret)
            },
            completion: completion
        )
    }

    private func parseQrRegistrationFields(_ qrData: String) -> [String: String] {
        var out: [String: String] = [:]
        let trimmed = qrData.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            out["vin"] = (json["vin"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
            out["sec"] = (json["sec"] as? String ?? json["secret"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out["code"] = (json["code"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out["broker"] = (json["broker"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out["plate"] = (json["plate"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
        } else if trimmed.lowercased().hasPrefix("changan://"),
                  let components = URLComponents(string: trimmed) {
            let items = components.queryItems ?? []
            var map: [String: String] = [:]
            for item in items { map[item.name] = item.value ?? "" }
            out["vin"] = (map["vin"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
            out["sec"] = (map["sec"] ?? map["secret"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out["code"] = (map["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out["broker"] = (map["broker"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out["plate"] = (map["plate"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
        } else if let range = trimmed.uppercased(with: Locale(identifier: "en_US_POSIX")).range(of: "[A-HJ-NPR-Z0-9]{17}", options: .regularExpression) {
            out["vin"] = String(trimmed[range]).uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
        return out
    }

    private func verifyPairConfirmWithAgent(
        pinCode: String,
        onSuccessCommit: (() -> Void)? = nil,
        onFailureRollback: (() -> Void)? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let owner = "\(userFirstName) \(userLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerName = owner.isEmpty ? "Avtomobil Sahibi" : owner
        let deviceName = "iPhone (\(UIDevice.current.model))"
        var params: [String: Any] = [
            "device": deviceName,
            "owner": ownerName,
            "code": pinCode,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        let plateTrim = carPlate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plateTrim.isEmpty { params["plate"] = plateTrim }

        Task { @MainActor in
            if !cloudConnected {
                let deadline = Date().addingTimeInterval(6.0)
                while !cloudConnected && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            guard let (msgId, payload) = CommandProtocol.createSignedCommand(
                action: "PAIR_CONFIRM",
                vin: vin,
                params: params,
                secret: secretKey
            ) else {
                onFailureRollback?()
                let err = "Cütləşmə paketi hazırlana bilmədi"
                toastMessage = err
                completion(false, err)
                return
            }

            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self else { return }
                if let waiter = self.ackWaiters.removeValue(forKey: msgId) {
                    waiter.resume(returning: (false, "Avtomobildən təsdiq cavabı gəlmədi (qoşulmanı yoxlayın)"))
                }
                self.pending.removeValue(forKey: msgId)
                self.pendingCommandCount = self.pending.count
            }
            pending[msgId] = PendingCommand(action: "PAIR_CONFIRM", timeoutTask: timeoutTask, silent: true, sentAt: Date(), optimisticKeys: [])
            pendingCommandCount = pending.count

            guard mqttClient.sendSignedCommand(payload, msgId: msgId) else {
                pending.removeValue(forKey: msgId)?.timeoutTask.cancel()
                pendingCommandCount = pending.count
                onFailureRollback?()
                let err = "Avtomobilə cütləşmə paketi göndərilə bilmədi"
                toastMessage = err
                completion(false, err)
                return
            }

            let res: (Bool, String) = await withCheckedContinuation { cont in
                ackWaiters[msgId] = cont
            }
            if res.0 {
                onSuccessCommit?()
                defaults.set(true, forKey: "is_vehicle_paired")
                isVehiclePaired = true
                toastMessage = "✅ Avtomobillə şifrəli cütləşmə təsdiqləndi!"
                completion(true, nil)
            } else {
                onFailureRollback?()
                let err = res.1.isEmpty ? "PİN / təhlükəsizlik təsdiqi rədd edildi" : res.1
                toastMessage = err
                completion(false, err)
            }
        }
    }

    // MARK: - Connection & Telemetry Lifecycle

    func toggleCloudConnection() {
        if mqttClient.state != .disconnected {
            manualCloudDisabled = true
            mqttClient.disconnect()
            showBanner("Bulud əlaqəsi dayandırıldı", severity: .info, channelLabel: "Bulud")
        } else {
            manualCloudDisabled = false
            mqttClient.connect()
        }
        updateConnectivity()
    }

    func reconnectCloud() {
        manualCloudDisabled = false
        mqttClient.reconnectNow()
        showBanner("Bulud bağlantısı yenilənir...", severity: .info, channelLabel: "Bulud")
    }

    func setAllowInsecureCustomTls(_ allow: Bool) {
        allowInsecureCustomTls = allow
        defaults.set(allow, forKey: "allow_insecure_custom_tls")
        mqttClient.allowInsecureCustomTls = allow
        mqttClient.reconnectNow()
    }

    func updateSettings(newBroker: String, newVin: String, newSecret: String) -> Bool {
        let broker = newBroker.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicleVin = newVin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
        let key = newSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBrokerUri(broker),
              vehicleVin.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
              key.count >= 16 else {
            toastMessage = "Broker və VIN-i yoxlayın; gizli açar ən azı 16 simvol olmalıdır"
            return false
        }

        let vinChanged = vehicleVin.caseInsensitiveCompare(vin) != .orderedSame
        stopLiveVideo()
        stopCabinAudioListening()
        stopLiveTalk()
        revResetTask?.cancel(); revResetTask = nil
        ventilationTask?.cancel(); ventilationTask = nil
        rapidVentRemainingSeconds = nil
        for keyId in Array(pending.keys) {
            finishCommand(keyId, text: "Ayarlar dəyişdi", isError: false)
        }
        optimisticRegistry.clearAll()
        parkChargeTask?.cancel(); parkChargeTask = nil
        parkChargeStarting = false
        wiperServiceActive = false
        mediaRequests.removeAll()

        brokerUrl = broker
        vin = vehicleVin
        secretKey = key
        defaults.set(broker, forKey: "broker_url")
        defaults.set(vehicleVin, forKey: "vin")
        defaults.set(key, forKey: "secret_key")

        if vinChanged {
            defaults.set(false, forKey: "is_vehicle_paired")
            isVehiclePaired = false
            agentPresenceOnline = false
            lastOnlineAt = nil
        }

        let empty = TelemetryState(vin: vehicleVin)
        lastConfirmedTelemetry = empty
        telemetry = empty
        mqttClient.updateConfig(brokerUrl: broker, vin: vehicleVin, secretKey: key)
        if !manualCloudDisabled {
            mqttClient.connect()
        }
        toastMessage = "Tənzimləmələr saxlanıldı; telefon və avtomobildə eyni olmalıdır"
        return true
    }

    private func isValidBrokerUri(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["tcp", "ssl", "ws", "wss"].contains(scheme),
              let host = url.host, !host.isEmpty,
              let port = url.port, (1...65535).contains(port) else {
            return false
        }
        return true
    }

    private func handlePresenceChanged(online: Bool, timestampSec: Int64) {
        let nowSec = Int64(Date().timeIntervalSince1970)
        let freshOnline = online && timestampSec > 0 && (-300...CommandProtocol.presenceOnlineStaleSeconds).contains(nowSec - timestampSec)
        agentPresenceOnline = freshOnline
        if freshOnline {
            telemetry.isPresenceOnline = true
            telemetry.lastCloudUpdateEpoch = max(telemetry.lastCloudUpdateEpoch, nowSec)
        } else {
            telemetry.isPresenceOnline = false
        }
        updateConnectivity()
        if freshOnline && (nowSec - telemetry.lastUpdateEpoch > 8) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                self?.forceRefresh(silent: true)
            }
        }
    }

    private func maybeSendKeepalivePing() {
        guard !vin.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSilentPingAt) >= CommandProtocol.pingIntervalSeconds else { return }
        guard cloudConnected else { return }
        let nowSec = Int64(now.timeIntervalSince1970)
        guard nowSec - telemetry.lastCloudUpdateEpoch >= 10 else { return }
        lastSilentPingAt = now
        _ = dispatchCommand(CommandProtocol.actionPing, params: [:], silent: true)
    }

    private func receiveTelemetry(_ state: TelemetryState) {
        if !vin.isEmpty && !state.vin.isEmpty && state.vin.caseInsensitiveCompare(vin) != .orderedSame { return }
        guard state.lastUpdateEpoch > 0 else { return }
        let nowSec = Int64(Date().timeIntervalSince1970)
        let lastCloud = state.isLiveCloudSample ? nowSec : telemetry.lastCloudUpdateEpoch
        if state.isLiveCloudSample { agentPresenceOnline = true }

        let base = lastConfirmedTelemetry
        let backwardCorrection = state.isLiveCloudSample && base.lastUpdateEpoch > 0 && (base.lastUpdateEpoch - state.lastUpdateEpoch) > 60
        let merged = (state.lastUpdateEpoch >= base.lastUpdateEpoch || base.lastUpdateEpoch <= 0 || backwardCorrection)
            ? state.mergeWithPrevious(base) : base

        lastConfirmedTelemetry = merged
        var applied = optimisticRegistry.applyTo(merged)
        applied.isDualSync = syncTemperatures
        applied.isCloudTransportConnected = cloudConnected
        applied.isPresenceOnline = agentPresenceOnline
        applied.lastCloudUpdateEpoch = lastCloud
        let cloudDelta = nowSec - lastCloud
        applied.isBrokerConnected = cloudConnected && (agentPresenceOnline || (lastCloud > 0 && (-30...CommandProtocol.telemetryOnlineStaleSeconds).contains(cloudDelta)))
        applied = evaluateOnlineWithGrace(applied, nowSec: nowSec)
        telemetry = applied
        wiperServiceActive = applied.wiperServiceMode
        updateConnectionUiState()

        if state.isLiveCloudSample {
            let localPlate = carPlate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !localPlate.isEmpty,
               localPlate.caseInsensitiveCompare(applied.agentVehiclePlate.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame,
               lastAutoSyncedPlate != localPlate,
               plateSyncInFlight != localPlate {
                plateSyncInFlight = localPlate
                setAgentSettings(["vehiclePlate": localPlate]) { [weak self] in
                    self?.lastAutoSyncedPlate = localPlate
                    if self?.plateSyncInFlight == localPlate { self?.plateSyncInFlight = nil }
                }
            }
        }
    }

    private func evaluateOnlineWithGrace(_ state: TelemetryState, nowSec: Int64) -> TelemetryState {
        var next = state
        if state.isCloudLive(nowSeconds: nowSec) {
            lastOnlineAt = Date()
            next.isConnected = true
            next.isReconnectingGrace = false
            return next
        }
        let recovering = (mqttClient.state == .connecting || mqttClient.state == .reconnecting) && !manualCloudDisabled
        let withinGrace = (lastOnlineAt.map { Date().timeIntervalSince($0) <= CommandProtocol.reconnectGraceSeconds } ?? false) && recovering
        next.isConnected = withinGrace
        next.isReconnectingGrace = withinGrace
        return next
    }

    private func updateConnectionUiState() {
        let cs: LinkHealthState
        switch mqttClient.state {
        case .disconnected: cs = .disconnected
        case .connecting: cs = .connecting
        case .reconnecting: cs = .reconnecting
        case .connected: cs = .connected
        }
        let next = ConnectionUiState(
            cloudState: cs,
            agentPresenceOnline: agentPresenceOnline,
            isReconnectingInGrace: telemetry.isReconnectingGrace,
            isOnline: telemetry.isConnected,
            cloudLatencyMs: cloudLatencyMs
        )
        if connectionUiState != next {
            connectionUiState = next
        }
    }

    private func updateConnectivity() {
        let nowSec = Int64(Date().timeIntervalSince1970)
        var cur = telemetry
        let delta = nowSec - cur.lastCloudUpdateEpoch
        cur.isCloudTransportConnected = cloudConnected
        cur.isPresenceOnline = agentPresenceOnline
        cur.isBrokerConnected = cloudConnected && (agentPresenceOnline || (cur.lastCloudUpdateEpoch > 0 && (-30...CommandProtocol.telemetryOnlineStaleSeconds).contains(delta)))
        cur = evaluateOnlineWithGrace(cur, nowSec: nowSec)
        telemetry = cur
        updateConnectionUiState()

        let onlineNow = cur.isConnected && !cur.isReconnectingGrace
        if onlineNow && !lastTrulyOnline {
            lastTrulyOnline = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.forceRefresh(silent: true)
            }
        } else if !cur.isConnected {
            lastTrulyOnline = false
        }
    }

    // MARK: - Command Dispatch & ACK Handling

    func isActionSupported(_ action: String) -> Bool {
        if alwaysAllowedActions.contains(action) { return true }
        return telemetry.supportedActions.contains(action)
    }

    func dismissCommandBanner() {
        bannerDismissTask?.cancel()
        commandBanner = nil
    }

    func confirmControlAction() {
        guard let req = controlConfirmation else { return }
        controlConfirmation = nil
        guard Date() <= req.expiresAt else {
            showBanner("Təsdiq vaxtı bitdi; düyməyə yenidən toxunun", severity: .info)
            return
        }
        var p = req.params
        if req.action == "OPEN_TRUNK" || req.action == "OPEN_FUEL_CAP" {
            p["confirmed"] = true
        }
        _ = dispatchCommand(req.action, params: p, confirmedByUser: true)
    }

    func cancelControlConfirmation() {
        controlConfirmation = nil
    }

    private func showBanner(_ text: String, severity: BannerSeverity, channelLabel: String? = nil, autoDismissMs: Int64 = 2600) {
        bannerDismissTask?.cancel()
        bannerSeq += 1
        let id = bannerSeq
        commandBanner = CommandBannerState(id: id, message: text, severity: severity, channelLabel: channelLabel, autoDismissMs: autoDismissMs)
        if autoDismissMs > 0 {
            bannerDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(autoDismissMs) * 1_000_000)
                if self?.commandBanner?.id == id {
                    self?.commandBanner = nil
                }
            }
        }
    }

    private func restoreTelemetryFromConfirmed() {
        var restored = optimisticRegistry.applyTo(lastConfirmedTelemetry)
        restored.isDualSync = telemetry.isDualSync
        restored.isBrokerConnected = telemetry.isBrokerConnected
        restored.isCloudTransportConnected = telemetry.isCloudTransportConnected
        restored.isPresenceOnline = telemetry.isPresenceOnline
        restored.lastCloudUpdateEpoch = telemetry.lastCloudUpdateEpoch
        restored.isConnected = telemetry.isConnected
        restored.isReconnectingGrace = telemetry.isReconnectingGrace
        telemetry = restored
        wiperServiceActive = restored.wiperServiceMode
    }

    @discardableResult
    private func dispatchCommand(
        _ action: String,
        params: [String: Any],
        confirmedByUser: Bool = false,
        silent: Bool = false,
        optimisticKeys: Set<String> = [],
        onDispatchedId: ((String) -> Void)? = nil
    ) -> Bool {
        if !confirmedByUser && (action == "OPEN_TRUNK" || action == "OPEN_FUEL_CAP") {
            let title = action == "OPEN_TRUNK" ? "Baqaj açılsın?" : "Benzin qapağı açılsın?"
            let msg = action == "OPEN_TRUNK"
                ? "Baqajı açdıqdan sonra onu avtomobilin yanında fiziki olaraq bağlamaq lazım gələcək. Davam edilsin?"
                : "Benzin qapağını açdıqdan sonra onu avtomobilin yanında fiziki olaraq bağlamaq lazım gələcək. Davam edilsin?"
            controlConfirmation = ControlConfirmation(action: action, title: title, message: msg, params: params, expiresAt: Date().addingTimeInterval(30))
            return false
        }

        let known = telemetry.supportedActions
        if action != CommandProtocol.actionPing && !known.isEmpty && !known.contains(action) && !alwaysAllowedActions.contains(action) {
            optimisticRegistry.releaseKeys(optimisticKeys, onlyUnattached: true)
            restoreTelemetryFromConfirmed()
            if action == "CAPTURE_CAMERA" { isCameraLoading = false }
            if !silent { showBanner("Bu funksiya hazırkı agentdə dəstəklənmir: \(action)", severity: .error) }
            return false
        }

        if pending.count >= 16 {
            optimisticRegistry.releaseKeys(optimisticKeys, onlyUnattached: true)
            restoreTelemetryFromConfirmed()
            if action == "CAPTURE_CAMERA" { isCameraLoading = false }
            if !silent { showBanner("Əvvəlki əmrlərin cavabını gözləyin", severity: .warning) }
            return false
        }

        guard let (id, payload) = CommandProtocol.createSignedCommand(action: action, vin: vin, params: params, secret: secretKey) else {
            optimisticRegistry.releaseKeys(optimisticKeys, onlyUnattached: true)
            restoreTelemetryFromConfirmed()
            if action == "CAPTURE_CAMERA" { isCameraLoading = false }
            if !silent { showBanner("Əmr hazırlana bilmədi", severity: .error) }
            return false
        }

        if !optimisticKeys.isEmpty {
            optimisticRegistry.attachMsgId(optimisticKeys, msgId: id)
        }

        let timeoutSec: Double = action == CommandProtocol.actionPing ? 6.0 : (mediaActions.contains(action) ? 60.0 : 18.0)
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
            guard let self else { return }
            self.finishCommand(id, text: "Avtomobildən cavab vaxtında gəlmədi", isError: true)
            self.mediaRequests.removeValue(forKey: id)
        }

        if action == "START_CAMERA_STREAM" { activeVideoId = id }
        if action == "START_CABIN_AUDIO_STREAM" { activeCabinAudioId = id }

        pending[id] = PendingCommand(action: action, timeoutTask: timeoutTask, silent: silent, sentAt: Date(), optimisticKeys: optimisticKeys)
        if mediaActions.contains(action) {
            mediaRequests[id] = Date().addingTimeInterval(timeoutSec)
        }
        onDispatchedId?(id)
        pendingCommandCount = pending.count

        if !silent {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                if self?.pending[id] != nil {
                    self?.showBanner("Təsdiq gözlənilir...", severity: .pending, channelLabel: "Bulud", autoDismissMs: 5000)
                }
            }
        }

        guard mqttClient.sendSignedCommand(payload, msgId: id) else {
            finishCommand(id, text: "Bulud bağlantısı hazır deyil", isError: true)
            return false
        }
        return true
    }

    private func finishCommand(_ id: String, text: String, isError: Bool = false, severityOverride: BannerSeverity? = nil) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeoutTask.cancel()
        if let waiter = ackWaiters.removeValue(forKey: id) {
            waiter.resume(returning: (!isError, text))
        }
        let pendingSnap = isError ? pendingAutoSaveSnapshotIds.removeValue(forKey: id) : nil
        pendingCommandCount = pending.count
        if item.action == "CAPTURE_CAMERA" { isCameraLoading = false }
        if isError {
            if let fallback = pendingSnap?.fallback { saveCameraSnapshot(fallback) }
            if id == activeVideoId { resetLiveVideoState(clearPending: false) }
            if id == activeCabinAudioId { resetCabinAudioState(clearPending: false) }
            if !item.optimisticKeys.isEmpty || ["SET_STANDBY_MODE", "SET_AGENT_SETTINGS", "REV_ENGINE_SOUND"].contains(item.action) {
                optimisticRegistry.releaseByMsgId(id)
                restoreTelemetryFromConfirmed()
            }
        }
        guard !item.silent else { return }
        let sev = severityOverride ?? (isError ? .error : .success)
        showBanner(text, severity: sev, channelLabel: "Bulud", autoDismissMs: sev != .success ? 3600 : 2400)
    }

    private func clearPendingSilently(_ id: String?) {
        guard let id, !id.isEmpty, let item = pending.removeValue(forKey: id) else { return }
        item.timeoutTask.cancel()
        ackWaiters.removeValue(forKey: id)?.resume(returning: (true, ""))
        pendingAutoSaveSnapshotIds.removeValue(forKey: id)
        pendingCommandCount = pending.count
    }

    private func handleAck(_ ack: [String: Any]) {
        let packetVin = (ack["vin"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !vin.isEmpty && packetVin.caseInsensitiveCompare(vin) != .orderedSame { return }
        let id = ack["msgId"] as? String ?? ""
        if id == talkStartId, let waiter = talkReadyWaiter {
            talkReadyWaiter = nil
            let ok = (ack["status"] as? String) == "SUCCESS"
            waiter.resume(returning: (ok, ack["details"] as? String ?? ""))
            return
        }
        guard let item = pending[id] else { return }
        cloudLatencyMs = max(1, Int64(Date().timeIntervalSince(item.sentAt) * 1000))
        updateConnectionUiState()

        if item.action == CommandProtocol.actionPing {
            pending.removeValue(forKey: id)?.timeoutTask.cancel()
            pendingCommandCount = pending.count
            let nowSec = Int64(Date().timeIntervalSince1970)
            agentPresenceOnline = true
            telemetry.lastCloudUpdateEpoch = nowSec
            telemetry.isPresenceOnline = true
            updateConnectivity()
            return
        }

        let status = ack["status"] as? String ?? ""
        let details = ack["details"] as? String ?? ""
        let ok = (status == "SUCCESS" || status == "ACCEPTED")
        ackWaiters.removeValue(forKey: id)?.resume(returning: (ok, details))
        if item.action == "PAIR_CONFIRM" {
            pending.removeValue(forKey: id)?.timeoutTask.cancel()
            pendingCommandCount = pending.count
            return
        }
        if item.action == "VENT_CABIN" && ok { beginVentilationCountdown() }
        if status == "ACCEPTED" && mediaActions.contains(item.action) {
            if !item.silent {
                showBanner("Agent qəbul etdi: \(details)", severity: .pending, channelLabel: "Bulud", autoDismissMs: 6000)
            }
            return
        }

        let isError = !["SUCCESS", "ACCEPTED", "CLARIFY"].contains(status)
        let sevOverride: BannerSeverity? = status == "BLOCKED" || status == "UNSUPPORTED" ? .warning : (status == "CLARIFY" ? .info : nil)
        let msg: String
        switch status {
        case "SUCCESS": msg = details.isEmpty ? "Avtomobil təsdiqlədi" : details
        case "ACCEPTED": msg = details.isEmpty ? "Əmr qəbul edildi" : details
        case "CLARIFY": msg = details.isEmpty ? "Əmri dəqiqləşdirin" : details
        case "BLOCKED": msg = details.isEmpty ? "Təhlükəsizlik qalxanı əmri blokladı" : details
        case "UNSUPPORTED": msg = "Bu funksiya avtomobildə dəstəklənmir: \(details)"
        default: msg = details.isEmpty ? "Əmr alınmadı (\(status))" : details
        }
        finishCommand(id, text: msg, isError: isError, severityOverride: sevOverride)
        if !ok {
            mediaRequests.removeValue(forKey: id)
            if item.action == "START_CAMERA_STREAM" && id == activeVideoId {
                resetLiveVideoState(clearPending: false)
            }
            if item.action == "START_CABIN_AUDIO_STREAM" && id == activeCabinAudioId {
                resetCabinAudioState(clearPending: false)
            }
        }
    }

    // MARK: - Media Packets (H.264, JPEG, Cabin Audio)

    private func handleMediaPacket(_ json: [String: Any]) {
        let msgId = json["msgId"] as? String ?? ""
        let type = json["type"] as? String ?? ""
        let packetVin = (json["vin"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !vin.isEmpty && packetVin.caseInsensitiveCompare(vin) != .orderedSame { return }
        let isAlarmSnap = type == "CAMERA_SNAPSHOT" && msgId.hasPrefix("alarm_")
        if !isAlarmSnap && mediaRequests[msgId] == nil && msgId != activeVideoId && msgId != activeCabinAudioId { return }

        if ["CAMERA_H264", "CAMERA_FRAME", "CABIN_AUDIO_FRAME"].contains(type) {
            mediaRequests[msgId] = Date().addingTimeInterval(15)
        }

        switch type {
        case "CAMERA_H264":
            guard isVideoStreaming, msgId == activeVideoId else { return }
            let seq = CommandProtocol.jsonInt(json["sequence"]) ?? 0
            let cfgStr = json["configBase64"] as? String ?? ""
            let cfgData = cfgStr.isEmpty ? nil : Data(base64Encoded: cfgStr)
            let restarted = ((json["streamRestart"] as? Bool) ?? false) || (seq == 1 && cfgData != nil)
            if !restarted && seq <= lastVideoSequence { return }
            lastVideoSequence = seq
            clearPendingSilently(msgId)

            let encoded = json["videoBase64"] as? String ?? ""
            guard !encoded.isEmpty, let frameData = Data(base64Encoded: encoded) else { return }
            let isKey = (json["keyFrame"] as? Bool) ?? false
            let ptsUs = (json["ptsUs"] as? NSNumber)?.int64Value ?? 0
            let w = max(16, CommandProtocol.jsonInt(json["width"]) ?? 640)
            let h = max(16, CommandProtocol.jsonInt(json["height"]) ?? 480)
            let bitrate = CommandProtocol.jsonInt(json["bitrateKbps"]) ?? 0

            if h264Decoder.submitFrame(frameBytes: frameData, configBytes: cfgData, isKeyFrame: isKey, ptsUs: ptsUs) {
                recordRenderedVideoFrame(bitrateKbps: bitrate)
            }
            videoWidth = w
            videoHeight = h
            videoAspectRatio = CGFloat(w) / CGFloat(h)
            isH264VideoActive = true
            isCameraLoading = false
            cameraTimestampMs = Int64(Date().timeIntervalSince1970 * 1000)

        case "CAMERA_FRAME", "CAMERA_SNAPSHOT":
            let isFrame = (type == "CAMERA_FRAME")
            if isFrame {
                let seq = CommandProtocol.jsonInt(json["sequence"]) ?? 0
                guard isVideoStreaming, msgId == activeVideoId, (seq == 1 || seq > lastVideoSequence) else { return }
                lastVideoSequence = seq
                recordRenderedVideoFrame(bitrateKbps: 0)
                clearPendingSilently(msgId)
            }
            let b64 = (json["imageBase64"] as? String) ?? (json["image_base64"] as? String) ?? ""
            guard (16...1_800_000).contains(b64.count),
                  let data = Data(base64Encoded: b64),
                  let img = UIImage(data: data) else {
                isCameraLoading = false
                return
            }
            if !isFrame {
                let autoEntry = pendingAutoSaveSnapshotIds.removeValue(forKey: msgId)
                if autoEntry != nil { saveCameraSnapshot(img) }
                if autoEntry == nil || !isH264VideoActive {
                    cameraImage = img
                    cameraTimestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                }
                mediaRequests.removeValue(forKey: msgId)
            } else {
                cameraImage = img
                cameraTimestampMs = Int64(Date().timeIntervalSince1970 * 1000)
            }
            isCameraLoading = false

        case "CABIN_AUDIO_FRAME":
            guard isCabinListening, (activeCabinAudioId == nil || msgId == activeCabinAudioId) else { return }
            clearPendingSilently(msgId.isEmpty ? nil : msgId)
            let seq = CommandProtocol.jsonInt(json["sequence"]) ?? 0
            if seq > 0 && seq <= lastAudioSequence { return }
            if seq > 0 { lastAudioSequence = seq }
            let encoded = json["audioBase64"] as? String ?? ""
            guard !encoded.isEmpty, encoded.count <= 65536, let pcm = Data(base64Encoded: encoded), !pcm.isEmpty else { return }
            let sr = min(max(CommandProtocol.jsonInt(json["sampleRate"]) ?? 8000, 8000), 48000)
            audioManager.playPcmChunk(pcm, sampleRate: sr)

        case "MEDIA_STATUS":
            if msgId == activeVideoId { resetLiveVideoState(clearPending: true) }
            if msgId == activeCabinAudioId { resetCabinAudioState(clearPending: true) }
            if let details = json["details"] as? String, !details.isEmpty {
                showBanner(details, severity: .info)
            }
            mediaRequests.removeValue(forKey: msgId)

        default: break
        }
    }

    private func recordRenderedVideoFrame(bitrateKbps: Int) {
        let now = Date()
        if let start = fpsWindowStart {
            fpsFrameCount += 1
            let elapsed = now.timeIntervalSince(start)
            if elapsed >= 1.0 {
                videoFps = min(60, max(0, Int(Double(fpsFrameCount) / elapsed)))
                fpsWindowStart = now
                fpsFrameCount = 0
            }
        } else {
            fpsWindowStart = now
            fpsFrameCount = 1
        }
        if bitrateKbps > 0 { videoBitrateKbps = bitrateKbps }
    }

    // MARK: - Vehicle Control Methods

    func forceRefresh(silent: Bool = false) {
        if silent {
            let now = Date()
            let nowSec = Int64(now.timeIntervalSince1970)
            if now.timeIntervalSince(lastSilentRefreshAt) < 3.0 || (0...2).contains(nowSec - telemetry.lastUpdateEpoch) {
                return
            }
            lastSilentRefreshAt = now
        }
        _ = dispatchCommand("FORCE_REFRESH", params: [:], silent: silent)
    }

    private func applyOptimistic(_ key: String, _ value: Any, updater: (inout TelemetryState) -> Void) -> Set<String> {
        optimisticRegistry.lockKey(key, expectedValue: value)
        updater(&telemetry)
        return [key]
    }

    func toggleDoorLock() {
        let next = !telemetry.doorsLocked
        let keys = applyOptimistic("doorsLocked", next) { $0.doorsLocked = next }
        _ = dispatchCommand(next ? "LOCK_DOORS" : "UNLOCK_DOORS", params: [:], optimisticKeys: keys)
    }

    func toggleWindows() {
        let anyOpen = telemetry.windowPositions.contains { $0 > 0 }
        let target = anyOpen ? 0 : 100
        optimisticRegistry.releaseKeys(["windowPos_0", "windowPos_1", "windowPos_2", "windowPos_3"])
        let keys = applyOptimistic("windowPositions", target) {
            $0.windowPositions = [target, target, target, target]
            $0.windowsClosed = (target == 0)
        }
        _ = dispatchCommand(anyOpen ? "CLOSE_WINDOWS" : "OPEN_WINDOWS", params: [:], optimisticKeys: keys)
    }

    func setIndividualWindow(windowArea: Int, percent: Int) {
        let clamped = min(max(percent, 0), 100)
        var indices: [Int] = []
        if windowArea == 0x55 {
            indices = [0, 1, 2, 3]
        } else {
            if (windowArea & 16) != 0 { indices.append(0) }
            if (windowArea & 64) != 0 { indices.append(1) }
            if (windowArea & 256) != 0 { indices.append(2) }
            if (windowArea & 1024) != 0 { indices.append(3) }
        }
        optimisticRegistry.releaseKeys(["windowPositions"])
        var keys: Set<String> = []
        for idx in indices {
            let k = "windowPos_\(idx)"
            optimisticRegistry.lockKey(k, expectedValue: clamped)
            keys.insert(k)
        }
        var updated = telemetry.windowPositions
        while updated.count < 4 { updated.append(0) }
        for idx in indices { updated[idx] = clamped }
        telemetry.windowPositions = updated
        telemetry.windowsClosed = updated.allSatisfy { $0 == 0 }
        _ = dispatchCommand("SET_WINDOW_POS", params: ["windowArea": windowArea, "percent": clamped], optimisticKeys: keys)
    }

    func setAllWindows(percent: Int) {
        let clamped = min(max(percent, 0), 100)
        if clamped == 0 || clamped == 100 {
            optimisticRegistry.releaseKeys(["windowPos_0", "windowPos_1", "windowPos_2", "windowPos_3"])
            let keys = applyOptimistic("windowPositions", clamped) {
                $0.windowPositions = [clamped, clamped, clamped, clamped]
                $0.windowsClosed = (clamped == 0)
            }
            _ = dispatchCommand(clamped == 0 ? "CLOSE_WINDOWS" : "OPEN_WINDOWS", params: [:], optimisticKeys: keys)
        } else {
            optimisticRegistry.releaseKeys(["windowPos_0", "windowPos_1", "windowPos_2", "windowPos_3"])
            let keys = applyOptimistic("windowPositions", clamped) {
                $0.windowPositions = [clamped, clamped, clamped, clamped]
                $0.windowsClosed = false
            }
            _ = dispatchCommand("SET_ALL_WINDOWS", params: ["percent": clamped], optimisticKeys: keys)
        }
    }

    func toggleSunroof() { setSunroof(percent: telemetry.sunroofPosition > 0 ? 0 : 100) }
    func setSunroof(percent: Int) {
        let clamped = min(max(percent, 0), 100)
        let keys = applyOptimistic("sunroofPosition", clamped) {
            $0.sunroofPosition = clamped
            $0.sunroofClosed = (clamped == 0)
        }
        _ = dispatchCommand("SET_SUNROOF_POS", params: ["percent": clamped], optimisticKeys: keys)
    }

    func tiltSunroof() {
        let keys = applyOptimistic("sunroofPosition", 101) {
            $0.sunroofPosition = 101
            $0.sunroofClosed = false
        }
        _ = dispatchCommand("TILT_SUNROOF", params: ["percent": 101, "tilt": true], optimisticKeys: keys)
    }

    func openTrunk() { _ = dispatchCommand("OPEN_TRUNK", params: [:]) }
    func openFuelCap() { _ = dispatchCommand("OPEN_FUEL_CAP", params: [:]) }
    func ventWindows() { _ = dispatchCommand("VENT_WINDOWS", params: ["ventilationPercent": 10]) }

    func triggerRapidVentilation() {
        if ventilationTask != nil || telemetry.ventilationStatus == "RUNNING" {
            ventilationTask?.cancel(); ventilationTask = nil; rapidVentRemainingSeconds = nil
            _ = dispatchCommand("STOP_VENT_CABIN", params: [:])
            return
        }
        guard !pending.values.contains(where: { $0.action == "VENT_CABIN" }) else { return }
        _ = dispatchCommand("VENT_CABIN", params: [:])
    }

    private func beginVentilationCountdown() {
        ventilationTask?.cancel()
        ventilationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for sec in stride(from: 30, through: 1, by: -1) {
                self.rapidVentRemainingSeconds = sec
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
            }
            self.rapidVentRemainingSeconds = nil
            self.ventilationTask = nil
        }
    }

    func toggleWiperServiceMode() {
        let next = !wiperServiceActive
        wiperServiceActive = next
        let keys = applyOptimistic("wiperServiceMode", next) { $0.wiperServiceMode = next }
        _ = dispatchCommand("SET_WIPER", params: ["mode": "MAINTENANCE", "enabled": next], optimisticKeys: keys)
    }

    func toggleHeadlights() {
        let next = !telemetry.headlightsOn
        let keys = applyOptimistic("headlightsOn", next) { $0.headlightsOn = next }
        _ = dispatchCommand("SET_LIGHTS", params: ["headlights": next], optimisticKeys: keys)
    }

    func startSelektor() {
        let keys = applyOptimistic("selektorOn", true) { $0.selektorOn = true }
        _ = dispatchCommand("SET_LIGHTS", params: ["selektor": true], silent: true, optimisticKeys: keys)
    }

    func stopSelektor() {
        let keys = applyOptimistic("selektorOn", false) { $0.selektorOn = false }
        _ = dispatchCommand("SET_LIGHTS", params: ["selektor": false], silent: true, optimisticKeys: keys)
    }

    func toggleDecorativeLight() {
        let next = !telemetry.decorativeLightOn
        let keys = applyOptimistic("decorativeLightOn", next) { $0.decorativeLightOn = next }
        _ = dispatchCommand("SET_LIGHTS", params: ["decorativeLight": next], optimisticKeys: keys)
    }

    func toggleFogLights() {
        let next = !telemetry.fogLightsOn
        let keys = applyOptimistic("fogLightsOn", next) { $0.fogLightsOn = next }
        _ = dispatchCommand("SET_LIGHTS", params: ["fogLights": next], optimisticKeys: keys)
    }

    func toggleDomeLight() {
        let next = !telemetry.domeLightOn
        let keys = applyOptimistic("domeLightOn", next) { $0.domeLightOn = next }
        _ = dispatchCommand("SET_LIGHTS", params: ["domeLight": next], optimisticKeys: keys)
    }

    func toggleAmbientLight() {
        let next = !telemetry.ambientLightOn
        if !next { optimisticRegistry.releaseKeys(["ambientBrightness"], onlyUnattached: false) }
        let keys = applyOptimistic("ambientLightOn", next) { $0.ambientLightOn = next }
        _ = dispatchCommand("SET_LIGHTS", params: ["ambientLight": next], optimisticKeys: keys)
    }

    func setAmbientBrightness(_ level: Int) {
        let clamped = min(max(level, 1), 6)
        optimisticRegistry.lockKey("ambientBrightness", expectedValue: clamped)
        optimisticRegistry.lockKey("ambientLightOn", expectedValue: true)
        telemetry.ambientBrightness = clamped
        telemetry.ambientLightOn = true
        _ = dispatchCommand("SET_LIGHTS", params: ["ambientBrightness": clamped, "ambientLight": true], optimisticKeys: ["ambientBrightness", "ambientLightOn"])
    }

    func setAmbientColor(_ color: Int) {
        let clamped = min(max(color, 1), 64)
        let keys = applyOptimistic("ambientColor", clamped) { $0.ambientColor = clamped }
        _ = dispatchCommand("SET_LIGHTS", params: ["ambientColor": clamped], optimisticKeys: keys)
    }

    func startHornHold() {
        _ = dispatchCommand("PLAY_AVAS_SOUND", params: ["sound": "vip_dual_tone", "volumeMode": "strong", "loop": true, "hornHold": true], silent: true)
    }

    func stopHornHold() {
        _ = dispatchCommand("STOP_AVAS_SOUND", params: [:], silent: true)
    }

    // MARK: - Climate Controls

    func toggleClimatePower() {
        let next = !telemetry.climatePower
        if !next {
            optimisticRegistry.lockKey("climatePower", expectedValue: false)
            optimisticRegistry.lockKey("fanSpeed", expectedValue: 0)
            telemetry.climatePower = false
            telemetry.fanSpeed = 0
            _ = dispatchCommand("CLIMATE_OFF", params: [:], optimisticKeys: ["climatePower", "fanSpeed"])
        } else {
            let targetFan = min(max(telemetry.fanSpeed, 3), 8)
            optimisticRegistry.lockKey("climatePower", expectedValue: true)
            optimisticRegistry.lockKey("fanSpeed", expectedValue: targetFan)
            telemetry.climatePower = true
            telemetry.fanSpeed = targetFan
            _ = dispatchCommand("SET_CLIMATE", params: ["power": true, "fanSpeed": targetFan], optimisticKeys: ["climatePower", "fanSpeed"])
        }
    }

    func setDriverTemperature(_ temp: Float) {
        guard temp.isFinite else { return }
        let clamped = min(max(temp, 17.5), 32.5)
        optimisticRegistry.lockKey("driverTemp", expectedValue: clamped)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        var keys: Set<String> = ["driverTemp", "climatePower"]
        var params: [String: Any] = ["driverTemp": Double(clamped), "power": true]
        if syncTemperatures {
            optimisticRegistry.lockKey("passengerTemp", expectedValue: clamped)
            keys.insert("passengerTemp")
            params["passengerTemp"] = Double(clamped)
            telemetry.passengerTemp = clamped
        }
        telemetry.driverTemp = clamped
        telemetry.targetTemp = clamped
        telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: params, optimisticKeys: keys)
    }

    func setFanSpeed(_ speed: Int) {
        let clamped = min(max(speed, 1), 8)
        optimisticRegistry.lockKey("fanSpeed", expectedValue: clamped)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.fanSpeed = clamped
        telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["fanSpeed": clamped, "power": true], optimisticKeys: ["fanSpeed", "climatePower"])
    }

    func setWindMode(_ mode: Int) {
        guard (1...6).contains(mode) else { return }
        if mode == 4 && (telemetry.defrost || telemetry.windMode == 4 || telemetry.windMode == 6) {
            optimisticRegistry.lockKey("windMode", expectedValue: 3)
            optimisticRegistry.lockKey("defrost", expectedValue: false)
            optimisticRegistry.lockKey("autoMode", expectedValue: false)
            optimisticRegistry.lockKey("climatePower", expectedValue: true)
            telemetry.windMode = 3; telemetry.defrost = false; telemetry.autoMode = false; telemetry.climatePower = true
            _ = dispatchCommand("SET_CLIMATE", params: ["defrost": false, "windMode": 3, "power": true], optimisticKeys: ["windMode", "defrost", "autoMode", "climatePower"])
            return
        }
        let defrostOn = (mode == 4)
        optimisticRegistry.lockKey("windMode", expectedValue: mode)
        optimisticRegistry.lockKey("defrost", expectedValue: defrostOn)
        optimisticRegistry.lockKey("autoMode", expectedValue: false)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.windMode = mode; telemetry.defrost = defrostOn; telemetry.autoMode = false; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["windMode": mode, "power": true], optimisticKeys: ["windMode", "defrost", "autoMode", "climatePower"])
    }

    func toggleAc() {
        let next = !telemetry.acCompressor
        optimisticRegistry.lockKey("acCompressor", expectedValue: next)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.acCompressor = next; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["acCompressor": next, "power": true], optimisticKeys: ["acCompressor", "climatePower"])
    }

    func toggleMaxAc() {
        let next = !telemetry.maxAc
        optimisticRegistry.lockKey("maxAc", expectedValue: next)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.maxAc = next; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["maxAc": next, "power": true], optimisticKeys: ["maxAc", "climatePower"])
    }

    func toggleAuto() {
        let next = !telemetry.autoMode
        optimisticRegistry.lockKey("autoMode", expectedValue: next)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.autoMode = next; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["autoMode": next, "power": true], optimisticKeys: ["autoMode", "climatePower"])
    }

    func toggleRearDefrost() {
        let next = !telemetry.rearDefrost
        let keys = applyOptimistic("rearDefrost", next) { $0.rearDefrost = next }
        _ = dispatchCommand("SET_CLIMATE", params: ["rearDefrost": next], optimisticKeys: keys)
    }

    func setRecirculation(_ enabled: BooleanLike) {
        optimisticRegistry.lockKey("recirculation", expectedValue: enabled)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.recirculation = enabled; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["recirculation": enabled, "power": true], optimisticKeys: ["recirculation", "climatePower"])
    }

    func toggleAutoDefog() {
        let next = !telemetry.autoDefog
        let keys = applyOptimistic("autoDefog", next) { $0.autoDefog = next }
        _ = dispatchCommand("SET_CLIMATE", params: ["autoDefog": next], optimisticKeys: keys)
    }

    func toggleAirDry() {
        let next = !telemetry.airDry
        let keys = applyOptimistic("airDry", next) { $0.airDry = next }
        _ = dispatchCommand("SET_CLIMATE", params: ["airDry": next], optimisticKeys: keys)
    }

    func toggleNaturalWind() {
        let next = !telemetry.naturalWind
        optimisticRegistry.lockKey("naturalWind", expectedValue: next)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.naturalWind = next; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["naturalWind": next, "power": true], optimisticKeys: ["naturalWind", "climatePower"])
    }

    func toggleEcoClimate() {
        let next = !telemetry.ecoClimate
        optimisticRegistry.lockKey("ecoClimate", expectedValue: next)
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        telemetry.ecoClimate = next; telemetry.climatePower = true
        _ = dispatchCommand("SET_CLIMATE", params: ["ecoMode": next, "power": true], optimisticKeys: ["ecoClimate", "climatePower"])
    }

    func toggleSmokeMode() {
        let next = !telemetry.smokeMode
        if next {
            let targetFan = max(telemetry.fanSpeed, 4)
            optimisticRegistry.lockKey("smokeMode", expectedValue: true)
            optimisticRegistry.lockKey("climatePower", expectedValue: true)
            optimisticRegistry.lockKey("recirculation", expectedValue: false)
            optimisticRegistry.lockKey("fanSpeed", expectedValue: targetFan)
            telemetry.smokeMode = true; telemetry.climatePower = true; telemetry.recirculation = false; telemetry.fanSpeed = targetFan
            _ = dispatchCommand("SET_CLIMATE", params: ["smokeMode": true, "power": true], optimisticKeys: ["smokeMode", "climatePower", "recirculation", "fanSpeed"])
        } else {
            let keys = applyOptimistic("smokeMode", false) { $0.smokeMode = false }
            _ = dispatchCommand("SET_CLIMATE", params: ["smokeMode": false], optimisticKeys: keys)
        }
    }

    func triggerQuickHeat() {
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        optimisticRegistry.lockKey("autoMode", expectedValue: false)
        optimisticRegistry.lockKey("acCompressor", expectedValue: false)
        optimisticRegistry.lockKey("driverTemp", expectedValue: Float(32.5))
        optimisticRegistry.lockKey("fanSpeed", expectedValue: 8)
        optimisticRegistry.lockKey("recirculation", expectedValue: true)
        optimisticRegistry.lockKey("windMode", expectedValue: 3)
        telemetry.climatePower = true; telemetry.autoMode = false; telemetry.acCompressor = false
        telemetry.driverTemp = 32.5; telemetry.targetTemp = 32.5; telemetry.fanSpeed = 8; telemetry.recirculation = true; telemetry.windMode = 3
        _ = dispatchCommand("QUICK_HEAT", params: [:], optimisticKeys: ["climatePower", "autoMode", "acCompressor", "driverTemp", "fanSpeed", "recirculation", "windMode"])
    }

    func triggerQuickCool() {
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        optimisticRegistry.lockKey("autoMode", expectedValue: false)
        optimisticRegistry.lockKey("driverTemp", expectedValue: Float(17.5))
        optimisticRegistry.lockKey("fanSpeed", expectedValue: 8)
        optimisticRegistry.lockKey("acCompressor", expectedValue: true)
        optimisticRegistry.lockKey("recirculation", expectedValue: true)
        telemetry.climatePower = true; telemetry.autoMode = false; telemetry.driverTemp = 17.5
        telemetry.targetTemp = 17.5; telemetry.fanSpeed = 8; telemetry.acCompressor = true; telemetry.recirculation = true
        _ = dispatchCommand("QUICK_COOL", params: [:], optimisticKeys: ["climatePower", "autoMode", "driverTemp", "fanSpeed", "acCompressor", "recirculation"])
    }

    func triggerDefog() {
        if telemetry.defrost || telemetry.windMode == 4 || telemetry.windMode == 6 {
            optimisticRegistry.lockKey("defrost", expectedValue: false)
            optimisticRegistry.lockKey("windMode", expectedValue: 3)
            optimisticRegistry.lockKey("fanSpeed", expectedValue: 3)
            telemetry.defrost = false; telemetry.windMode = 3; telemetry.fanSpeed = 3
            _ = dispatchCommand("SET_CLIMATE", params: ["defrost": false, "windMode": 3, "fanSpeed": 3], optimisticKeys: ["defrost", "windMode", "fanSpeed"])
            return
        }
        optimisticRegistry.lockKey("climatePower", expectedValue: true)
        optimisticRegistry.lockKey("autoMode", expectedValue: false)
        optimisticRegistry.lockKey("fanSpeed", expectedValue: 8)
        optimisticRegistry.lockKey("recirculation", expectedValue: false)
        optimisticRegistry.lockKey("acCompressor", expectedValue: true)
        optimisticRegistry.lockKey("defrost", expectedValue: true)
        optimisticRegistry.lockKey("windMode", expectedValue: 4)
        telemetry.climatePower = true; telemetry.autoMode = false; telemetry.fanSpeed = 8
        telemetry.recirculation = false; telemetry.acCompressor = true; telemetry.defrost = true; telemetry.windMode = 4
        _ = dispatchCommand("SET_CLIMATE", params: ["power": true, "autoMode": false, "fanSpeed": 8, "recirculation": false, "acCompressor": true, "defrost": true], optimisticKeys: ["climatePower", "autoMode", "fanSpeed", "recirculation", "acCompressor", "defrost", "windMode"])
    }

    // MARK: - More Screen: Park Charge, Light Show, AVAS, Agent Settings, GPS

    private func isVehicleRunningState(_ t: TelemetryState) -> Bool {
        t.energyMode == "REMOTE_ACTIVE" ||
        t.energyMode == "FACTORY_AWAKE" ||
        t.ignitionState >= 3 ||
        (t.ignitionState >= 2 && t.energyMode != "PASSIVE" && t.energyMode != "PASSIVE_OFF")
    }

    func startParkCharge(targetSoc: Int) {
        let clamped = min(max(targetSoc, 15), 80)
        let cur = telemetry
        let notInPark = (!cur.gear.isEmpty && cur.gear.caseInsensitiveCompare("P") != .orderedSame) || (cur.vehicleSpeed.isFinite && cur.vehicleSpeed > 1.5)
        if notInPark {
            showBanner("Park Şarj yalnız P rejimində tam dayanarkən işləyir", severity: .warning)
            return
        }
        parkChargeTask?.cancel()
        if isVehicleRunningState(cur) {
            parkChargeStarting = false
            setDriveMode("SCENARIO", subMode: "PARK_CHARGE", targetSoc: clamped)
            return
        }
        parkChargeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.parkChargeStarting = true
            defer { self.parkChargeStarting = false }
            self.showBanner("Mühərrik işə salınır, ardından Park Şarj (\(clamped)%) aktivləşdiriləcək…", severity: .info)
            _ = self.dispatchCommand("REMOTE_START", params: [:])
            let deadline = Date().addingTimeInterval(15.0)
            var becameRunning = false
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                if self.isVehicleRunningState(self.telemetry) {
                    becameRunning = true
                    break
                }
            }
            guard becameRunning else {
                self.showBanner("Mühərrik işə düşmədi; Park Şarj başladılmadı", severity: .warning)
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.setDriveMode("SCENARIO", subMode: "PARK_CHARGE", targetSoc: clamped)
        }
    }

    func updateParkChargeTargetSoc(_ targetSoc: Int) {
        setDriveMode("SCENARIO", subMode: "PARK_CHARGE", targetSoc: min(max(targetSoc, 15), 80))
    }

    func stopParkCharge(stopEngine: Bool = false) {
        parkChargeTask?.cancel(); parkChargeTask = nil; parkChargeStarting = false
        setDriveMode("EV")
        if stopEngine {
            parkChargeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                _ = self?.dispatchCommand("REMOTE_STOP", params: [:])
            }
        }
    }

    private func setDriveMode(_ mode: String, subMode: String? = nil, targetSoc: Int? = nil) {
        let fullMode = subMode != nil ? "\(mode)_\(subMode!)" : mode
        optimisticRegistry.lockKey("driveMode", expectedValue: fullMode)
        var keys: Set<String> = ["driveMode"]
        if let targetSoc {
            optimisticRegistry.lockKey("saveTargetSoc", expectedValue: targetSoc)
            keys.insert("saveTargetSoc")
            telemetry.saveTargetSoc = targetSoc
        }
        telemetry.driveMode = mode
        telemetry.driveSubMode = subMode ?? ""
        var params: [String: Any] = ["mode": mode]
        if let subMode { params["subMode"] = subMode }
        if let targetSoc { params["targetSoc"] = targetSoc }
        _ = dispatchCommand("SET_DRIVE_MODE", params: params, optimisticKeys: keys)
    }

    func toggleSafetyMode() {
        let next = !telemetry.safetyArmed
        let keys = applyOptimistic("safetyArmed", next) { $0.safetyArmed = next }
        _ = dispatchCommand("SET_SAFETY_MODE", params: ["armed": next], optimisticKeys: keys)
    }

    func startLightShow(
        profile: String = "BEAT_SYNC",
        audioRoute: String = "DUAL",
        track: String = "user_hero",
        cabinVolume: Float = 0.70,
        avasVolume: Float = 0.85,
        ventWindows: BooleanLike = false,
        headlights: Bool = true,
        highBeams: Bool = true,
        turnSignals: Bool = true,
        widthLamps: Bool = true
    ) {
        let params: [String: Any] = [
            "profile": profile,
            "audioRoute": audioRoute,
            "track": track,
            "cabinVolume": Double(cabinVolume),
            "avasVolume": Double(avasVolume),
            "ventWindows": ventWindows,
            "lights": [
                "headlights": headlights,
                "highBeams": highBeams,
                "turnSignals": turnSignals,
                "widthLamps": widthLamps,
                "mirrors": false
            ]
        ]
        _ = dispatchCommand("START_LIGHT_SHOW", params: params)
    }

    func stopLightShow() {
        _ = dispatchCommand("STOP_LIGHT_SHOW", params: [:])
    }

    func setEngineSound(enabled: Bool, profile: String? = nil, volume: String? = nil) {
        let p = profile ?? telemetry.engineSoundProfile
        let v = volume ?? telemetry.engineSoundVolume
        let keys = applyOptimistic("engineSoundEnabled", enabled) {
            $0.engineSoundEnabled = enabled
            $0.engineSoundProfile = p
            $0.engineSoundVolume = v
        }
        _ = dispatchCommand("SET_ENGINE_SOUND", params: ["enabled": enabled, "profile": p, "volume": v], optimisticKeys: keys)
    }

    func revEngineSound(throttlePercent: Int = 92, durationMs: Int = 2400, profile: String? = nil, volume: String? = nil) {
        let thr = min(max(throttlePercent, 15), 100)
        let dur = min(max(durationMs, 800), 6000)
        let p = profile ?? telemetry.engineSoundProfile
        let v = volume ?? telemetry.engineSoundVolume
        guard dispatchCommand("REV_ENGINE_SOUND", params: ["throttlePercent": thr, "durationMs": dur, "profile": p, "volume": v]) else { return }
        if telemetry.isConnected {
            let baseEpoch = lastConfirmedTelemetry.lastUpdateEpoch
            telemetry.engineSoundEnabled = true
            telemetry.engineSoundProfile = p
            telemetry.engineSoundVolume = v
            telemetry.throttlePercent = thr
            telemetry.virtualRpm = 6200
            revResetTask?.cancel()
            revResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(dur + 400) * 1_000_000)
                if self?.lastConfirmedTelemetry.lastUpdateEpoch == baseEpoch {
                    self?.restoreTelemetryFromConfirmed()
                }
            }
        }
    }

    func setAvasVolumeTier(_ tier: String) {
        avasVolumeTier = tier
        defaults.set(tier, forKey: "avas_volume_tier")
        let vol: Float = tier == "weak" ? 0.4 : (tier == "normal" ? 1.0 : 2.5)
        setAvasVolume(vol)
    }

    func setAvasVolume(_ volume: Float) {
        let clamped = min(max(volume, 0.1), 3.0)
        avasVolume = clamped
        defaults.set(clamped, forKey: "avas_volume")
        if let session = currentLiveSession, isTalking,
           let (_, payload) = CommandProtocol.createSignedCommand(
            action: "AVAS_TALK",
            vin: vin,
            params: ["sessionId": session, "op": "volume", "volume": Double(clamped), "sentAt": Int64(Date().timeIntervalSince1970 * 1000)],
            secret: secretKey
           ) {
            _ = mqttClient.sendLiveAudio(payload)
        }
    }

    func playAvasSound(_ soundId: String, loop: Bool = false) {
        _ = dispatchCommand("PLAY_AVAS_SOUND", params: ["sound": soundId, "volumeMode": avasVolumeTier, "loop": loop])
    }

    func stopAvasSound() {
        _ = dispatchCommand("STOP_AVAS_SOUND", params: [:])
    }

    func startLiveTalk() {
        guard !isTalking else { return }
        guard cloudConnected else {
            showBanner("Canlı səs üçün Bulud bağlantısı lazımdır", severity: .warning)
            return
        }
        audioManager.requestMicrophonePermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.showBanner("Meqafon üçün mikrofon icazəsi lazımdır", severity: .warning)
                return
            }
            self.beginLiveTalkSession()
        }
    }

    private func beginLiveTalkSession() {
        guard !isTalking else { return }
        isTalking = true
        let session = UUID().uuidString.lowercased()
        currentLiveSession = session
        talkSeq = 0

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let (startMsgId, startPayload) = CommandProtocol.createSignedCommand(
                action: "AVAS_TALK",
                vin: vin,
                params: ["sessionId": session, "op": "start", "volume": Double(avasVolume), "sentAt": Int64(Date().timeIntervalSince1970 * 1000)],
                secret: secretKey
            ) else {
                self.isTalking = false
                self.currentLiveSession = nil
                return
            }
            talkStartId = startMsgId
            guard mqttClient.sendLiveAudio(startPayload) else {
                self.isTalking = false
                self.currentLiveSession = nil
                self.showBanner("Canlı səs kanalı hazır deyil", severity: .error)
                return
            }

            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if let waiter = self?.talkReadyWaiter {
                    self?.talkReadyWaiter = nil
                    waiter.resume(returning: (false, "Avtomobil audio çıxışı vaxtında cavab vermədi"))
                }
            }
            let (opened, reason): (Bool, String) = await withCheckedContinuation { cont in
                talkReadyWaiter = cont
            }
            timeoutTask.cancel()
            guard opened, currentLiveSession == session, isTalking else {
                self.stopLiveTalk()
                if !reason.isEmpty { self.showBanner("Canlı səs: \(reason)", severity: .error) }
                return
            }

            showBanner("Canlı səs xarici dinamikə ötürülür; dayandırmaq üçün buraxın", severity: .info)
            audioManager.startMicCapture(
                onChunk: { [weak self] pcmData in
                    Task { @MainActor [weak self] in
                        guard let self, self.isTalking, self.currentLiveSession == session else { return }
                        let seq = self.talkSeq
                        self.talkSeq += 1
                        let params: [String: Any] = [
                            "sessionId": session,
                            "op": "pcm",
                            "seq": seq,
                            "pcm": pcmData.base64EncodedString(),
                            "sentAt": Int64(Date().timeIntervalSince1970 * 1000)
                        ]
                        if let (_, payload) = CommandProtocol.createSignedCommand(action: "AVAS_TALK", vin: self.vin, params: params, secret: self.secretKey) {
                            _ = self.mqttClient.sendLiveAudio(payload)
                        }
                    }
                },
                onError: { [weak self] msg in
                    Task { @MainActor [weak self] in
                        self?.showBanner(msg, severity: .error)
                        self?.stopLiveTalk()
                    }
                }
            )
        }
    }

    func stopLiveTalk() {
        audioManager.stopMicCapture()
        if let waiter = talkReadyWaiter {
            talkReadyWaiter = nil
            waiter.resume(returning: (false, ""))
        }
        let session = currentLiveSession
        currentLiveSession = nil
        talkStartId = nil
        let wasTalking = isTalking
        isTalking = false
        if wasTalking, let session,
           let (_, payload) = CommandProtocol.createSignedCommand(
            action: "AVAS_TALK",
            vin: vin,
            params: ["sessionId": session, "op": "stop", "sentAt": Int64(Date().timeIntervalSince1970 * 1000)],
            secret: secretKey
           ) {
            _ = mqttClient.sendLiveAudio(payload)
        }
    }

    func setStandbyMode(_ enabled: Bool) {
        let keys = applyOptimistic("standbyKeepalive", enabled) { $0.standbyKeepalive = enabled }
        if !dispatchCommand("SET_STANDBY_MODE", params: ["standbyKeepalive": enabled], optimisticKeys: keys) {
            restoreTelemetryFromConfirmed()
        }
    }

    func setAgentSettings(_ params: [String: Any], onApplied: (() -> Void)? = nil) {
        var lockedKeys: Set<String> = []
        if let v = params["autoMuteAvas"] as? Bool { optimisticRegistry.lockKey("agentAutoMuteAvas", expectedValue: v); lockedKeys.insert("agentAutoMuteAvas"); telemetry.agentAutoMuteAvas = v }
        if let v = params["lockChimeEnabled"] as? Bool { optimisticRegistry.lockKey("agentLockChimeEnabled", expectedValue: v); lockedKeys.insert("agentLockChimeEnabled"); telemetry.agentLockChimeEnabled = v }
        if let v = params["radioRecovery"] as? Bool { optimisticRegistry.lockKey("agentRadioRecovery", expectedValue: v); lockedKeys.insert("agentRadioRecovery"); telemetry.agentRadioRecovery = v }
        if let v = params["autoClimate"] as? Bool { optimisticRegistry.lockKey("agentAutoClimate", expectedValue: v); lockedKeys.insert("agentAutoClimate"); telemetry.agentAutoClimate = v }
        if let v = params["lsCabinVolumePercent"] as? Int { telemetry.agentLsCabinVolumePct = v }
        if let v = params["lsAvasVolumePercent"] as? Int { telemetry.agentLsAvasVolumePct = v }
        if let v = params["vehiclePlate"] as? String { telemetry.agentVehiclePlate = v }

        var sentId: String?
        let ok = dispatchCommand("SET_AGENT_SETTINGS", params: params, silent: onApplied != nil && params.keys.count == 1 && params["vehiclePlate"] != nil, optimisticKeys: lockedKeys) { sentId = $0 }
        if !ok {
            restoreTelemetryFromConfirmed()
            return
        }
        if let onApplied, let sentId {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let res: (Bool, String) = await withCheckedContinuation { cont in
                    self.ackWaiters[sentId] = cont
                }
                if res.0 { onApplied() }
            }
        }
    }

    func runFullDiagnostics() {
        _ = dispatchCommand("RUN_FULL_DIAGNOSTICS", params: [:])
    }

    func openCarMap() {
        guard telemetry.latitude.isFinite, telemetry.longitude.isFinite, telemetry.locationEpoch > 0 else {
            showBanner("Avtomobildən GPS mövqeyi alınmayıb", severity: .info)
            forceRefresh(silent: true)
            return
        }
        let age = Int64(Date().timeIntervalSince1970) - telemetry.locationEpoch
        guard (-30...120).contains(age) else {
            showBanner("GPS mövqeyi köhnədir; yeniləmə sorğusu göndərildi", severity: .info)
            forceRefresh(silent: true)
            return
        }
        if let url = URL(string: "http://maps.apple.com/?ll=\(telemetry.latitude),\(telemetry.longitude)&q=Changan") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Live Video & Cabin Audio

    func startLiveVideo(cameraId: String) {
        guard !isVideoStreaming else { return }
        guard telemetry.isBrokerConnected else {
            showBanner("Kamera üçün avtomobillə canlı bağlantı yoxdur", severity: .info)
            return
        }
        lastVideoSequence = 0
        fpsWindowStart = nil
        fpsFrameCount = 0
        videoFps = 0
        videoBitrateKbps = 0
        h264Decoder.reset()
        isH264VideoActive = false
        cameraImage = nil
        cameraTimestampMs = 0
        isVideoStreaming = true

        guard dispatchCommand("START_CAMERA_STREAM", params: ["cameraId": cameraId, "transport": "MQTT"]),
              let stream = activeVideoId else {
            isVideoStreaming = false
            return
        }

        liveVideoKeepaliveTask?.cancel()
        liveVideoKeepaliveTask = Task { @MainActor [weak self] in
            let end = Date().addingTimeInterval(600)
            var misses = 0
            while !Task.isCancelled, let self, self.isVideoStreaming, self.activeVideoId == stream, Date() < end {
                let needIdr = self.isH264VideoActive && self.h264Decoder.isAwaitingKeyFrame()
                let kaParams: [String: Any] = [
                    "streamId": stream,
                    "dropped": 0,
                    "queueDepth": 0,
                    "rxFps": self.videoFps,
                    "requestIdr": needIdr
                ]
                var sent = false
                if let (_, payload) = CommandProtocol.createSignedCommand(action: "CAMERA_KEEPALIVE", vin: self.vin, params: kaParams, secret: self.secretKey) {
                    sent = self.mqttClient.sendLiveAudio(payload)
                }
                if !sent {
                    misses += 1
                    if misses >= 6 {
                        self.stopLiveVideo()
                        self.showBanner("Video bağlantısı kəsildi", severity: .error)
                        return
                    }
                } else {
                    misses = 0
                }
                self.mediaRequests[stream] = Date().addingTimeInterval(15)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            if self?.isVideoStreaming == true, self?.activeVideoId == stream {
                self?.stopLiveVideo()
            }
        }
    }

    func switchLiveCamera(_ cameraId: String) {
        guard isVideoStreaming, let stream = activeVideoId else {
            startLiveVideo(cameraId: cameraId)
            return
        }
        h264Decoder.waitForKeyframe()
        _ = dispatchCommand("CAMERA_SWITCH", params: ["streamId": stream, "cameraId": cameraId, "transport": "MQTT"], silent: true)
    }

    func stopLiveVideo() {
        let stream = activeVideoId
        let wasStreaming = isVideoStreaming
        resetLiveVideoState(clearPending: true)
        if wasStreaming, let stream {
            _ = dispatchCommand("STOP_CAMERA_STREAM", params: ["streamId": stream])
        }
    }

    private func resetLiveVideoState(clearPending: Bool) {
        liveVideoKeepaliveTask?.cancel()
        liveVideoKeepaliveTask = nil
        let stream = activeVideoId
        activeVideoId = nil
        if let stream {
            mediaRequests.removeValue(forKey: stream)
            if clearPending { clearPendingSilently(stream) }
        }
        h264Decoder.reset()
        isVideoStreaming = false
        isH264VideoActive = false
        isCameraLoading = false
        videoFps = 0
        videoBitrateKbps = 0
        fpsWindowStart = nil
        fpsFrameCount = 0
    }

    func captureAndSaveHighResSnapshot(cameraId: String, fallbackImage: UIImage? = nil) {
        guard !isCameraLoading else { return }
        let targetId = cameraId.isEmpty ? (telemetry.cameraIds.first ?? "evs_front") : cameraId
        isCameraLoading = true
        let ok = dispatchCommand("CAPTURE_CAMERA", params: ["camera": targetId, "cameraId": targetId]) { [weak self] msgId in
            self?.pendingAutoSaveSnapshotIds[msgId] = (Date().addingTimeInterval(30), fallbackImage)
        }
        if !ok {
            isCameraLoading = false
            if let fallbackImage { saveCameraSnapshot(fallbackImage) }
            return
        }
        showBanner("Yüksək keyfiyyətli orijinal kadr çəkilir…", severity: .info)
    }

    func saveCameraSnapshot(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor [weak self] in
                    self?.showBanner("Şəkli saxlamaq üçün Qalereya icazəsi lazımdır", severity: .warning)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, err in
                Task { @MainActor [weak self] in
                    if ok {
                        self?.showBanner("Kadr iPhone Qalereyasına saxlanıldı", severity: .success)
                    } else {
                        self?.showBanner("Şəkil saxlanıla bilmədi: \(err?.localizedDescription ?? "")", severity: .error)
                    }
                }
            }
        }
    }

    func toggleCabinAudioListening() {
        if isCabinListening {
            stopCabinAudioListening()
        } else {
            startCabinAudioListening()
        }
    }

    private func startCabinAudioListening() {
        guard !isCabinListening else { return }
        guard telemetry.isBrokerConnected else {
            showBanner("Salon səsi üçün avtomobillə canlı bağlantı yoxdur", severity: .info)
            return
        }
        cabinListenKeepaliveTask?.cancel()
        lastAudioSequence = 0
        isCabinListening = true
        guard dispatchCommand("START_CABIN_AUDIO_STREAM", params: ["transport": "MQTT", "keepalive": true]) else {
            isCabinListening = false
            return
        }
        cabinListenKeepaliveTask = Task { @MainActor [weak self] in
            let end = Date().addingTimeInterval(600)
            while !Task.isCancelled, let self, self.isCabinListening, Date() < end {
                if let activeId = self.activeCabinAudioId {
                    self.mediaRequests[activeId] = Date().addingTimeInterval(15)
                    if let (_, kaPayload) = CommandProtocol.createSignedCommand(action: "CABIN_AUDIO_KEEPALIVE", vin: self.vin, params: ["streamId": activeId], secret: self.secretKey) {
                        _ = self.mqttClient.sendLiveAudio(kaPayload)
                    }
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            if self?.isCabinListening == true {
                self?.stopCabinAudioListening()
            }
        }
    }

    func stopCabinAudioListening() {
        let wasListening = isCabinListening
        resetCabinAudioState(clearPending: true)
        if wasListening {
            _ = dispatchCommand("STOP_CABIN_AUDIO_STREAM", params: [:])
        }
    }

    private func resetCabinAudioState(clearPending: Bool) {
        cabinListenKeepaliveTask?.cancel()
        cabinListenKeepaliveTask = nil
        let prev = activeCabinAudioId
        activeCabinAudioId = nil
        if let prev {
            mediaRequests.removeValue(forKey: prev)
            if clearPending { clearPendingSilently(prev) }
        }
        isCabinListening = false
        lastAudioSequence = 0
        audioManager.stopPlayback()
    }
}

typealias BooleanLike = Bool
