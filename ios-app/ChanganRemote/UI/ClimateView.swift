import SwiftUI

struct ClimateView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel

    @State private var draftTemp: Float = 25.0
    @State private var draftFan: Float = 5.0
    @State private var isTempDragging = false
    @State private var isFanDragging = false

    private let windModes: [(code: Int, label: String, icon: String)] = [
        (1, "Üzə", "person.crop.circle"),
        (2, "Ayağa", "figure.stand"),
        (3, "Üz + Ayaq", "arrow.up.and.down"),
        (4, "Ön Şüşə", "windshield.front.and.heat.waves"),
        (5, "Şüşə + Ayaq", "wind")
    ]

    var body: some View {
        let t = viewModel.telemetry
        let online = t.isConnected

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Klimat idarəetməsi")
                                .font(.title2.weight(.bold))
                            Text("Yeniləndi: \(t.lastSeenDescription())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { viewModel.forceRefresh() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                        }
                    }

                    // Main Climate Card
                    VStack(spacing: 14) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                let cabinText = (online && t.cabinTemp.isFinite && t.cabinTemp > -40 && t.cabinTemp < 80)
                                    ? String(format: "%.1f°C", t.cabinTemp) : "—"
                                let outsideText = (online && t.outsideTemp.isFinite && t.outsideTemp > -50 && t.outsideTemp < 80)
                                    ? String(format: "%.1f°C", t.outsideTemp) : "—"
                                let targetText = formatTargetTemp(connected: online, driverTempKnown: t.driverTemp.isFinite, verbose: false)

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(cabinText)
                                        .font(.system(size: 38, weight: .heavy))
                                        .foregroundStyle(online && t.climatePower ? Color.accentColor : Color.primary)
                                    Text("Hədəf: \(targetText)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                Text("Çöl: \(outsideText)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                            }

                            Spacer()

                            let isPowerOn = online && t.climatePower
                            Button {
                                if online { viewModel.toggleClimatePower() }
                                else { viewModel.forceRefresh() }
                            } label: {
                                Image(systemName: "power")
                                    .font(.system(size: 24, weight: .bold))
                                    .frame(width: 54, height: 54)
                                    .background((!online ? Color.gray : (isPowerOn ? Color.green : Color.red)).opacity(0.16), in: Circle())
                                    .overlay(Circle().stroke(!online ? Color.gray : (isPowerOn ? Color.green : Color.red), lineWidth: 1.8))
                                    .foregroundStyle(!online ? Color.gray : (isPowerOn ? Color.green : Color.red))
                            }
                        }

                        Divider()

                        // Temperature Slider (17.5 .. 32.5 step 0.5)
                        VStack(spacing: 4) {
                            HStack {
                                Text("Temperatur").font(.caption.weight(.bold))
                                Spacer()
                                Text(formatTargetTemp(connected: online, driverTempKnown: t.driverTemp.isFinite, verbose: true))
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.tint)
                            }
                            Slider(value: Binding(
                                get: { Double(draftTemp) },
                                set: { draftTemp = Float($0) }
                            ), in: 17.5...32.5, step: 0.5) { editing in
                                isTempDragging = editing
                                if !editing && online {
                                    viewModel.setDriverTemperature(draftTemp)
                                }
                            }
                            .disabled(!online)
                        }

                        // Fan Speed Slider (1 .. 8)
                        VStack(spacing: 4) {
                            HStack {
                                Text("Fan sürəti").font(.caption.weight(.bold))
                                Spacer()
                                Text(online ? "\(Int(draftFan)) / 8" : "—")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            Slider(value: Binding(
                                get: { Double(draftFan) },
                                set: { draftFan = Float($0) }
                            ), in: 1...8, step: 1) { editing in
                                isFanDragging = editing
                                if !editing && online {
                                    viewModel.setFanSpeed(Int(draftFan.rounded()))
                                }
                            }
                            .disabled(!online)
                        }

                        Divider()

                        // Wind Modes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hava axını istiqaməti").font(.caption.weight(.bold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(windModes, id: \.code) { wm in
                                        let active = online && (t.windMode == wm.code || (wm.code == 4 && (t.defrost || t.windMode == 6)))
                                        Button {
                                            viewModel.setWindMode(wm.code)
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: wm.icon).font(.system(size: 16))
                                                Text(wm.label).font(.caption2.weight(.semibold))
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(active ? Color.accentColor : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                                            .foregroundStyle(active ? .white : .primary)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!online)
                                    }
                                }
                            }
                        }

                        Divider()

                        // Mode Toggles Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ClimateToggleChip(title: "A/C", icon: "snowflake", active: online && t.acCompressor, enabled: online) { viewModel.toggleAc() }
                            ClimateToggleChip(title: "Max A/C", icon: "wind.snow", active: online && t.maxAc, enabled: online) { viewModel.toggleMaxAc() }
                            ClimateToggleChip(title: "AUTO", icon: "a.circle.fill", active: online && t.autoMode, enabled: online) { viewModel.toggleAuto() }
                            ClimateToggleChip(title: "Arxa Şüşə", icon: "heat.element.windshield", active: online && t.rearDefrost, enabled: online) { viewModel.toggleRearDefrost() }
                            ClimateToggleChip(title: "Sirkulyasiya", icon: "arrow.triangle.2.circlepath", active: online && t.recirculation, enabled: online) { viewModel.setRecirculation(!t.recirculation) }
                            ClimateToggleChip(title: "Auto Defog", icon: "drop.triangle.fill", active: online && t.autoDefog, enabled: online) { viewModel.toggleAutoDefog() }
                            ClimateToggleChip(title: "Hava Qurutma", icon: "humidity.fill", active: online && t.airDry, enabled: online) { viewModel.toggleAirDry() }
                            ClimateToggleChip(title: "Təbii Külək", icon: "leaf.fill", active: online && t.naturalWind, enabled: online) { viewModel.toggleNaturalWind() }
                            ClimateToggleChip(title: "ECO İqlim", icon: "bolt.shield.fill", active: online && t.ecoClimate, enabled: online) { viewModel.toggleEcoClimate() }
                            ClimateToggleChip(title: "Tüstü Rejimi", icon: "smoke.fill", active: online && t.smokeMode, enabled: online) { viewModel.toggleSmokeMode() }
                        }

                        Divider()

                        // Quick Presets
                        Text("Sürətli rejimlər").font(.caption.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Button {
                                viewModel.triggerQuickCool()
                            } label: {
                                Label("Tez Soyut", systemImage: "snowflake")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .disabled(!online)

                            Button {
                                viewModel.triggerQuickHeat()
                            } label: {
                                Label("Tez İsit", systemImage: "flame.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(!online)

                            Button {
                                viewModel.triggerDefog()
                            } label: {
                                Label("Tər Sil", systemImage: "wind")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(!online)
                        }
                    }
                    .padding(16)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
                }
                .padding(.horizontal)
                .padding(.bottom, 84)
            }
            .onAppear {
                viewModel.forceRefresh(silent: true)
            }
            .onChange(of: t.driverTemp) { _, newVal in
                if !isTempDragging && newVal.isFinite && newVal > 0 {
                    draftTemp = min(max(newVal, 17.5), 32.5)
                }
            }
            .onChange(of: t.fanSpeed) { _, newFan in
                if !isFanDragging && (1...8).contains(newFan) {
                    draftFan = Float(newFan)
                }
            }
        }
    }

    private func formatTargetTemp(connected: Bool, driverTempKnown: Bool, verbose: Bool) -> String {
        if (!connected && !isTempDragging) || (!isTempDragging && !driverTempKnown) { return "—" }
        if draftTemp <= 17.5 { return verbose ? "LO (17.5°)" : "LO" }
        if draftTemp >= 32.5 { return verbose ? "HI (32.5°)" : "HI" }
        return String(format: "%.1f°C", draftTemp)
    }
}

private struct ClimateToggleChip: View {
    let title: String
    let icon: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.45)
        .disabled(!enabled)
    }
}
