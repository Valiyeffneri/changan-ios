import SwiftUI

struct RemoteControlView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel
    let onOpenSettings: () -> Void

    @State private var showWindowSliders = false
    @State private var windowSliderValues: [Double] = [0, 0, 0, 0]
    @State private var sunroofSliderValue: Double = 0
    @State private var isDraggingWindow = [false, false, false, false]
    @State private var isDraggingSunroof = false

    private let ambientColors: [(code: Int, color: Color)] = [
        (1, Color(red: 0.22, green: 0.74, blue: 0.97)),
        (10, Color(red: 0.51, green: 0.55, blue: 0.97)),
        (22, Color(red: 0.91, green: 0.47, blue: 0.98)),
        (34, Color(red: 0.98, green: 0.44, blue: 0.52)),
        (46, Color(red: 0.98, green: 0.75, blue: 0.14)),
        (58, Color(red: 0.20, green: 0.83, blue: 0.60))
    ]

    var body: some View {
        let t = viewModel.telemetry
        let online = t.isConnected
        let isRunning = online && (
            t.energyMode == "REMOTE_ACTIVE" ||
            t.energyMode == "FACTORY_AWAKE" ||
            t.ignitionState >= 3 ||
            (t.ignitionState >= 2 && t.energyMode != "PASSIVE" && t.energyMode != "PASSIVE_OFF")
        )

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.carBrand) \(viewModel.carModel)")
                                .font(.title2.weight(.heavy))
                            let subtitle = !viewModel.carPlate.isEmpty
                                ? (!viewModel.carYear.isEmpty ? "\(viewModel.carYear) • \(viewModel.carPlate)" : viewModel.carPlate)
                                : "Changan Intelligent"
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { viewModel.forceRefresh() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                        }
                        Button { onOpenSettings() } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                        }
                        .padding(.leading, 6)
                    }

                    // Status & Telemetry Hero Card
                    VStack(spacing: 12) {
                        HStack {
                            let statusLabel = !online ? "Oflayn" : (t.isReconnectingGrace ? "Bağlantı bərpa olunur" : (isRunning ? "İşləyir" : "Dayanıb (\(t.gear.isEmpty ? "P" : t.gear))"))
                            Text(statusLabel)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background((online ? Color.accentColor : Color.gray).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(online ? Color.accentColor : Color.secondary)

                            Text(t.lastSeenDescription())
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            // Bluetooth (BLE) Status Badge
                            Button {
                                viewModel.toggleBluetoothConnection()
                            } label: {
                                let isBt = viewModel.btState == .connected
                                let isBtConn = viewModel.btState == .connecting
                                Label(
                                    isBt ? "BT aktiv" : (isBtConn ? "BT..." : "BT"),
                                    systemImage: isBt ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                                )
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background((isBt ? Color.accentColor : Color.secondary).opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(isBt ? Color.accentColor : .secondary)
                            }

                            // Cloud Status Badge
                            Button {
                                if viewModel.connectionUiState.cloudState == .connected {
                                    viewModel.forceRefresh()
                                } else {
                                    viewModel.reconnectCloud()
                                }
                            } label: {
                                let cloudOnline = t.isBrokerConnected && (viewModel.connectionUiState.cloudState == .connected || viewModel.connectionUiState.isReconnectingInGrace)
                                Label(
                                    cloudOnline ? "Bulud aktiv" : (viewModel.connectionUiState.cloudState == .connecting ? "Qoşulur..." : "Bulud"),
                                    systemImage: cloudOnline ? "icloud.fill" : "icloud.slash"
                                )
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background((cloudOnline ? Color.green : Color.secondary).opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(cloudOnline ? .green : .secondary)
                            }
                        }

                        // Car Silhouette Hero (No yellow headlight glow, no tire pressure bars)
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.12), Color.secondary.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: 118)

                            HStack(spacing: 22) {
                                Image(systemName: t.doorsLocked ? "car.side.lock.fill" : "car.side.fill")
                                    .font(.system(size: 54))
                                    .foregroundStyle(online ? Color.accentColor : Color.secondary)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 14) {
                                        HeroMetric(label: "Batareya", value: online && (0...100).contains(t.batterySoc) ? "\(t.batterySoc)%" : "—", tint: .green)
                                        HeroMetric(label: "Yanacaq", value: online && (0...100).contains(t.fuelPercent) ? "\(t.fuelPercent)%" : "—", tint: .orange)
                                        HeroMetric(label: "Ümumi yürüş", value: online && t.totalRangeKm >= 0 ? "\(t.totalRangeKm) km" : "—", tint: .primary)
                                    }
                                    HStack(spacing: 14) {
                                        let cabin = (online && t.cabinTemp.isFinite && t.cabinTemp > -40 && t.cabinTemp < 85) ? String(format: "%.1f°C", t.cabinTemp) : "—"
                                        let outside = (online && t.outsideTemp.isFinite && t.outsideTemp > -50 && t.outsideTemp < 85) ? String(format: "%.1f°C", t.outsideTemp) : "—"
                                        HeroMetric(label: "Salon", value: cabin, tint: .primary)
                                        HeroMetric(label: "Çöl", value: outside, tint: .secondary)
                                        HeroMetric(label: "12V", value: online && t.batteryVoltage12V.isFinite ? String(format: "%.1fV", t.batteryVoltage12V) : "—", tint: .blue)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // Vehicle Control Grid (Kuzov və Şüşə İdarəetməsi)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Avtomobil idarəetməsi")
                            .font(.headline)

                        let anyWindowOpen = t.windowPositions.contains { $0 > 0 }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ActionGridButton(
                                title: t.doorsLocked ? "Qapılar Kilidli" : "Qapılar Açıq",
                                icon: t.doorsLocked ? "lock.fill" : "lock.open.fill",
                                active: online && t.doorsLocked,
                                enabled: online
                            ) { viewModel.toggleDoorLock() }

                            ActionGridButton(
                                title: anyWindowOpen ? "Şüşələri Bağla" : "Şüşələri Aç",
                                icon: "window.vertical.closed",
                                active: online && anyWindowOpen,
                                enabled: online
                            ) { viewModel.toggleWindows() }

                            ActionGridButton(
                                title: t.sunroofPosition > 0 ? "Lyuku Bağla" : "Lyuku Aç",
                                icon: "sun.max.fill",
                                active: online && t.sunroofPosition > 0,
                                enabled: online
                            ) { viewModel.toggleSunroof() }

                            ActionGridButton(
                                title: "Lyuk Havalandır",
                                icon: "wind",
                                active: online && t.sunroofPosition == 101,
                                enabled: online
                            ) { viewModel.tiltSunroof() }

                            ActionGridButton(
                                title: "Havalandır (10%)",
                                icon: "aqi.low",
                                active: false,
                                enabled: online
                            ) { viewModel.ventWindows() }

                            ActionGridButton(
                                title: "Şüşəsilən Servis",
                                icon: "wiper.and.drop",
                                active: online && viewModel.wiperServiceActive,
                                enabled: online
                            ) { viewModel.toggleWiperServiceMode() }

                            ActionGridButton(
                                title: t.trunkOpen ? "Baqaj Açıqdır" : "Baqajı Aç",
                                icon: "car.rear.and.tire.marks",
                                active: online && t.trunkOpen,
                                enabled: online
                            ) { viewModel.openTrunk() }

                            ActionGridButton(
                                title: t.fuelDoorOpen == true ? "Bak Qapağı Açıq" : "Bak Qapağını Aç",
                                icon: "fuelpump.fill",
                                active: online && (t.fuelDoorOpen == true),
                                enabled: online
                            ) { viewModel.openFuelCap() }

                            let ventSec = viewModel.rapidVentRemainingSeconds
                            ActionGridButton(
                                title: ventSec != nil ? "Soyudur (\(ventSec!)s)" : "Sürətli Ventilyasiya",
                                icon: "fanblades.fill",
                                active: online && (ventSec != nil || t.ventilationStatus == "RUNNING"),
                                enabled: online
                            ) { viewModel.triggerRapidVentilation() }
                        }

                        // Hold Actions (Selektor & Horn)
                        HStack(spacing: 10) {
                            HoldActionButton(
                                title: "Selektor (Fara Çax)",
                                icon: "lightbulb.max.fill",
                                enabled: online,
                                onPressStart: { viewModel.startSelektor() },
                                onPressEnd: { viewModel.stopSelektor() }
                            )

                            HoldActionButton(
                                title: "Siqnal (Saxla)",
                                icon: "speaker.wave.3.fill",
                                enabled: online,
                                onPressStart: { viewModel.startHornHold() },
                                onPressEnd: { viewModel.stopHornHold() }
                            )
                        }
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // Lights & Ambient Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("İşıqlandırma və Ambiyans")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ActionGridButton(title: "Faralar", icon: "headlight.low.beam.fill", active: online && t.headlightsOn, enabled: online) { viewModel.toggleHeadlights() }
                            ActionGridButton(title: "Dekorativ", icon: "sparkles", active: online && t.decorativeLightOn, enabled: online) { viewModel.toggleDecorativeLight() }
                            ActionGridButton(title: "Duman", icon: "headlight.fog.fill", active: online && t.fogLightsOn, enabled: online) { viewModel.toggleFogLights() }
                            ActionGridButton(title: "Salon İşıq", icon: "lamp.ceiling.fill", active: online && t.domeLightOn, enabled: online) { viewModel.toggleDomeLight() }
                        }

                        Toggle("Salon Ambiyans İşığı", isOn: Binding(
                            get: { online && t.ambientLightOn },
                            set: { _ in viewModel.toggleAmbientLight() }
                        ))
                        .disabled(!online)

                        if online && t.ambientLightOn {
                            HStack(spacing: 10) {
                                Text("Parlaqlıq: \(t.ambientBrightness)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: Binding(
                                    get: { Double(t.ambientBrightness) },
                                    set: { viewModel.setAmbientBrightness(Int($0.rounded())) }
                                ), in: 1...6, step: 1)
                            }
                            HStack(spacing: 10) {
                                ForEach(ambientColors, id: \.code) { preset in
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle().stroke(Color.primary, lineWidth: t.ambientColor == preset.code ? 2.5 : 0)
                                        )
                                        .onTapGesture {
                                            viewModel.setAmbientColor(preset.code)
                                        }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // Expandable Fine Window & Sunroof Sliders
                    DisclosureGroup("Fərdi şüşə və lyuk dərəcəsi (%)", isExpanded: $showWindowSliders) {
                        VStack(spacing: 10) {
                            let names = ["Ön sol", "Ön sağ", "Arxa sol", "Arxa sağ"]
                            let areas = [16, 64, 256, 1024]
                            ForEach(0..<4, id: \.self) { idx in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(names[idx]).font(.caption.weight(.semibold))
                                        Spacer()
                                        Text("\(Int(windowSliderValues[idx]))%").font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $windowSliderValues[idx], in: 0...100, step: 5) { editing in
                                        isDraggingWindow[idx] = editing
                                        if !editing && online {
                                            viewModel.setIndividualWindow(windowArea: areas[idx], percent: Int(windowSliderValues[idx]))
                                        }
                                    }
                                    .disabled(!online)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Lyuk").font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(sunroofSliderValue > 100 ? "Havalandırma" : "\(Int(sunroofSliderValue))%").font(.caption.monospacedDigit())
                                }
                                Slider(value: $sunroofSliderValue, in: 0...100, step: 5) { editing in
                                    isDraggingSunroof = editing
                                    if !editing && online {
                                        viewModel.setSunroof(percent: Int(sunroofSliderValue))
                                    }
                                }
                                .disabled(!online)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal)
                .padding(.bottom, 84)
            }
            .onChange(of: t.windowPositions) { _, pos in
                for i in 0..<4 where i < pos.count && !isDraggingWindow[i] && (0...100).contains(pos[i]) {
                    windowSliderValues[i] = Double(pos[i])
                }
            }
            .onChange(of: t.sunroofPosition) { _, pos in
                if !isDraggingSunroof && (0...100).contains(pos) {
                    sunroofSliderValue = Double(pos)
                }
            }
        }
    }
}

private struct HeroMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(tint)
        }
    }
}

private struct ActionGridButton: View {
    let title: String
    let icon: String
    let active: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(active ? .white : (enabled ? Color.accentColor : Color.secondary))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(active ? .white : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.horizontal, 4)
            .background(active ? Color.accentColor : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.45)
        .disabled(!enabled)
    }
}

private struct HoldActionButton: View {
    let title: String
    let icon: String
    let enabled: Bool
    let onPressStart: () -> Void
    let onPressEnd: () -> Void

    @State private var isPressed = false

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background((isPressed ? Color.orange : Color.secondary.opacity(0.16)), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(isPressed ? .white : .primary)
            .opacity(enabled ? 1.0 : 0.45)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !isPressed else { return }
                        isPressed = true
                        onPressStart()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onPressEnd()
                    }
            )
            .onDisappear {
                if isPressed {
                    isPressed = false
                    onPressEnd()
                }
            }
    }
}
