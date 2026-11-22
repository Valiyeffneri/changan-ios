import SwiftUI

struct VehicleStatusView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel

    var body: some View {
        let t = viewModel.telemetry
        let online = t.isConnected

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avtomobil məlumatları")
                                .font(.title2.weight(.bold))
                            Text(t.lastUpdateEpoch > 0 ? "Son yenilənmə: \(t.lastSeenDescription())" : "Bağlantı gözlənilir")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Skan et") {
                            viewModel.runFullDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!online)

                        Button { viewModel.forceRefresh() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                        }
                    }

                    // Connectivity & Overview
                    StatusSectionCard(title: "Əsas Xülasə") {
                        StatusGrid(items: [
                            ("Alışdırma", !online ? "—" : ignitionLabel(t.ignitionState, ready: t.isCabinReady)),
                            ("Enerji rejimi", online && !t.energyMode.isEmpty ? energyModeLabel(t.energyMode) : "—"),
                            ("HV Batareya", online && (0...100).contains(t.batterySoc) ? "\(t.batterySoc)%" : "—"),
                            ("Ümumi yürüş", online && t.totalRangeKm >= 0 ? "\(t.totalRangeKm) km" : "—"),
                            ("Odometr", online && t.odometerKm.isFinite && t.odometerKm >= 0 ? "\(Int(t.odometerKm)) km" : "—"),
                            ("Ötürücü", online && !t.gear.isEmpty ? t.gear : "—")
                        ])
                    }

                    // PHEV & Battery
                    StatusSectionCard(title: "Batareya və Hibrid Sistemi (PHEV)") {
                        StatusGrid(items: [
                            ("EV məsafə", online && t.evRangeKm >= 0 ? "\(t.evRangeKm) km" : "—"),
                            ("Benzin məsafə", online && t.fuelRangeKm >= 0 ? "\(t.fuelRangeKm) km" : "—"),
                            ("Yanacaq (%)", online && (0...100).contains(t.fuelPercent) ? "\(t.fuelPercent)%" : "—"),
                            ("HV Gərginlik", online && t.hvVoltage.isFinite ? String(format: "%.1f V", t.hvVoltage) : "—"),
                            ("HV Güc", online && t.hvPowerKw.isFinite ? String(format: "%.1f kW", t.hvPowerKw) : "—"),
                            ("SOH", online && t.batterySoh.isFinite ? String(format: "%.1f%%", t.batterySoh) : "—"),
                            ("Şarj statusu", !online ? "—" : (t.isCharging ? "Şarj olunur" : "Dayanıb")),
                            ("12V Akumulyator", online && t.batteryVoltage12V.isFinite ? String(format: "%.2f V", t.batteryVoltage12V) : "—")
                        ])
                    }

                    // Engine & Temps
                    StatusSectionCard(title: "Mühərrik və Temperatur") {
                        StatusGrid(items: [
                            ("Soyutma mayesi", online && t.coolantTempC.isFinite ? String(format: "%.0f°C", t.coolantTempC) : "—"),
                            ("Yağ temp.", online && t.oilTempC.isFinite ? String(format: "%.0f°C", t.oilTempC) : "—"),
                            ("Mühərrik RPM", online && t.engineRpm >= 0 ? "\(t.engineRpm)" : "—"),
                            ("Sürət", online && t.vehicleSpeed.isFinite ? String(format: "%.0f km/s", t.vehicleSpeed) : "—"),
                            ("İnverter temp.", online && t.inverterTempC.isFinite ? String(format: "%.0f°C", t.inverterTempC) : "—"),
                            ("Motor temp.", online && t.motorTempC.isFinite ? String(format: "%.0f°C", t.motorTempC) : "—")
                        ])
                    }

                    // Tires (iTPMS / TPMS)
                    StatusSectionCard(title: "Təkər Nəzarəti (TPMS)") {
                        StatusGrid(items: [
                            ("Ön Sol", tireSummary(online: online, status: t.tireStatusFl, temp: t.tireTempFl, pressure: t.tirePressureFl)),
                            ("Ön Sağ", tireSummary(online: online, status: t.tireStatusFr, temp: t.tireTempFr, pressure: t.tirePressureFr)),
                            ("Arxa Sol", tireSummary(online: online, status: t.tireStatusRl, temp: t.tireTempRl, pressure: t.tirePressureRl)),
                            ("Arxa Sağ", tireSummary(online: online, status: t.tireStatusRr, temp: t.tireTempRr, pressure: t.tirePressureRr))
                        ])
                    }

                    // Doors & Body
                    StatusSectionCard(title: "Kuzov, Qapılar və DVR") {
                        StatusGrid(items: [
                            ("Qapı kilidi", !online ? "—" : (t.doorsLocked ? "Kilidli" : "Açıq")),
                            ("Şüşələr", !online ? "—" : (t.windowsClosed ? "Hamısı bağlı" : "Açıq")),
                            ("Lyuk", !online ? "—" : (t.sunroofPosition == 0 ? "Bağlı" : (t.sunroofPosition == 101 ? "Havalandırma" : "\(t.sunroofPosition)%"))),
                            ("Baqaj", !online ? "—" : (t.trunkOpen ? "Açıq" : "Bağlı")),
                            ("DVR yaddaş", online && t.dvrStoragePercent >= 0 ? "\(t.dvrStoragePercent)%" : "—"),
                            ("GPS peyklər", online && t.gpsSatellites >= 0 ? "\(t.gpsSatellites)" : "—")
                        ])
                    }

                    // ECU / DTC Diagnostics
                    if !t.dtcCodes.isEmpty || !t.panelWarnings.isEmpty || !t.ecuModules.isEmpty {
                        StatusSectionCard(title: "ECU və Xəta Kodları") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(t.dtcCodes) { dtc in
                                    HStack {
                                        Text(dtc.code).font(.caption.monospaced().weight(.bold)).foregroundStyle(.red)
                                        Text(dtc.description).font(.caption).foregroundStyle(.primary)
                                    }
                                }
                                ForEach(t.ecuModules) { mod in
                                    HStack {
                                        Text(mod.code).font(.caption.monospaced().weight(.bold))
                                        Text(mod.name).font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(mod.status).font(.caption2.weight(.bold)).foregroundStyle(mod.status == "OK" ? .green : .orange)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 84)
            }
            .onAppear {
                viewModel.forceRefresh(silent: true)
            }
        }
    }

    private func ignitionLabel(_ state: Int, ready: Bool) -> String {
        if ready || state == 4 { return "READY (İşlək)" }
        switch state {
        case 0: return "Sönülü (OFF)"
        case 2: return "ACC / Standbay"
        case 3: return "ON (Alışdırma)"
        default: return "Naməlum"
        }
    }

    private func energyModeLabel(_ mode: String) -> String {
        switch mode {
        case "REMOTE_ACTIVE": return "Uzaqdan aktiv"
        case "FACTORY_AWAKE": return "Oyaqdır"
        case "PASSIVE", "PASSIVE_OFF": return "Yuxu / Standbay"
        default: return mode
        }
    }

    private func tireSummary(online: Bool, status: String, temp: Int, pressure: Float) -> String {
        guard online else { return "—" }
        var parts: [String] = []
        if pressure.isFinite { parts.append(String(format: "%.1f bar", pressure)) }
        else if !status.isEmpty { parts.append(status) }
        if (-50...150).contains(temp) { parts.append("\(temp)°C") }
        return parts.isEmpty ? "Normal" : parts.joined(separator: " · ")
    }
}

private struct StatusSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct StatusGrid: View {
    let items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.0).font(.caption2).foregroundStyle(.secondary)
                    Text(pair.1).font(.subheadline.weight(.bold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
