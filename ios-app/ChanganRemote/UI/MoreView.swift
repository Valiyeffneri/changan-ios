import SwiftUI

private struct SoundSignalItem: Identifiable {
    let id: String
    let name: String
    let desc: String
}

struct MoreView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel
    let onOpenSettings: () -> Void

    @State private var targetSoc: Int = 50
    @State private var isTargetSocDragging = false

    @State private var lsProfile = "BEAT_SYNC"
    @State private var lsRoute = "DUAL"
    @State private var lsTrack = "user_hero"
    @State private var lsCabinVol: Float = 0.70
    @State private var lsAvasVol: Float = 0.85
    @State private var isCabinVolDragging = false
    @State private var isAvasVolDragging = false
    @State private var lsVentWindows = false
    @State private var lsHeadlights = true
    @State private var lsHighBeams = true
    @State private var lsTurnSignals = true
    @State private var lsWidthLamps = true

    @State private var draftAvasVolume: Float = 1.0
    @State private var isAvasVolumeDragging = false
    @State private var selectedSoundTab = "polis"
    @State private var holdingSoundId: String?

    private let soundCategories: [(key: String, title: String, items: [SoundSignalItem])] = [
        ("polis", "Polis", [
            SoundSignalItem(id: "police_yelp", name: "Polis fiti (Yelp)", desc: "Kəskin kəsik fit"),
            SoundSignalItem(id: "police_wail", name: "Polis sireni (Wail)", desc: "Klassik polis sireni"),
            SoundSignalItem(id: "police_phaser", name: "Faza / Hi-Lo", desc: "Sürətli iki tonlu siren"),
            SoundSignalItem(id: "kryakalka", name: "Kryakalka VIP", desc: "Xüsusi AVAS klakson"),
            SoundSignalItem(id: "police_euro_hilo", name: "Avropa YPX Hi-Lo", desc: "Polis iki-tonlu çağırış"),
            SoundSignalItem(id: "police_short_bark", name: "Polis qısa klik", desc: "Sürətli ikili xəbərdarlıq")
        ]),
        ("ambulans", "Təcili", [
            SoundSignalItem(id: "ambulance_wail", name: "Təcili yardım (Wail)", desc: "Klassik ambulans sireni"),
            SoundSignalItem(id: "ambulance_two_tone", name: "Avro Təcili (Martin)", desc: "İki tonlu Avropa tonu"),
            SoundSignalItem(id: "ambulance_chirp", name: "Təcili Çirp", desc: "Kəsişmə xəbərdarlıq siqnalı"),
            SoundSignalItem(id: "fire_airhorn", name: "Yanğın Airhorn", desc: "Ağır hava klaksonu"),
            SoundSignalItem(id: "rescue_sweep", name: "Xilasetmə Dalğa", desc: "Geniş tezlikli süpürmə"),
            SoundSignalItem(id: "priority_buzz", name: "Prioritet Siqnal", desc: "Yol açma impulsu")
        ]),
        ("vip", "VIP", [
            SoundSignalItem(id: "vip_horn", name: "VIP Buynuz (Federal)", desc: "Ağır kortej siqnalı"),
            SoundSignalItem(id: "dang_dang", name: "Dang-Dang", desc: "Məşhur eskort zəngi"),
            SoundSignalItem(id: "vip_dual_tone", name: "Qoşa Ton Kortej", desc: "Maybach iki tezlikli klakson"),
            SoundSignalItem(id: "vip_siren", name: "VIP Sirena", desc: "Müşayiət xüsusi fiti"),
            SoundSignalItem(id: "vip_escort_pulse", name: "Eskort İmpuls", desc: "Kortej ritmik siqnal"),
            SoundSignalItem(id: "vip_diplomat", name: "Diplomat Fara-Buynuz", desc: "Rəsmi ikili buynuz")
        ]),
        ("fun", "Klassik", [
            SoundSignalItem(id: "special_train", name: "Qatar Buynuzu", desc: "Güclü lokomotiv fiti"),
            SoundSignalItem(id: "special_ship", name: "Gəmi Fiti", desc: "Dəniz layner duman fiti"),
            SoundSignalItem(id: "truck_airhorn", name: "TIR Hava Buynuzu", desc: "Ağır yük maşını klaksonu"),
            SoundSignalItem(id: "fun_ahooga", name: "Retro Ahooga", desc: "1930-cu il klassik siqnal"),
            SoundSignalItem(id: "classic_dixie", name: "Klassik Melodiya", desc: "Klassik avtomobil fanfarı"),
            SoundSignalItem(id: "fun_cucaracha", name: "Kukaraça Buynuz", desc: "Məşhur Kukaraça melodiyası")
        ]),
        ("special", "Xüsusi", [
            SoundSignalItem(id: "signal_user_real", name: "1. Sizin Real Siqnal", desc: "Mastered real WAV siqnal"),
            SoundSignalItem(id: "fun_wedding", name: "Toy / Bayram Siqnal", desc: "Milli şənlik ritmi"),
            SoundSignalItem(id: "fun_boing", name: "Kiber Bounce", desc: "Futuristik yay effekti"),
            SoundSignalItem(id: "fun_quack", name: "Ördək / Zarafat", desc: "Əyləncəli ördək klakson"),
            SoundSignalItem(id: "sonar_ping", name: "Sonar Radarı", desc: "Dərin sualtı sonar tonu"),
            SoundSignalItem(id: "laser_lock", name: "Lazer Xəbərdarlıq", desc: "Yüksək texnoloji impuls")
        ])
    ]

    private let engineProfiles: [(code: String, label: String)] = [
        ("REAL_CUSTOM", "Real mühərrik"), ("BMW_M_V8", "BMW M V8"), ("AMG_BITURBO", "AMG Biturbo"),
        ("GT_SPORT", "Porsche GT3"), ("LAMBO_V10", "Lambo V10"), ("FERRARI_V12", "Ferrari V12"),
        ("GTR_TURBO", "GT-R R35 Turbo"), ("MUSCLE_V8", "Muscle V8"), ("RALLY_BOXER", "Rally WRC"), ("CYBER_TURBINE", "Kiber Turbin")
    ]

    var body: some View {
        let t = viewModel.telemetry
        let online = t.isConnected
        let parkChargeActive = online && t.driveMode == "SCENARIO" && t.driveSubMode == "PARK_CHARGE"

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daha çox").font(.title2.weight(.bold))
                            Text("Xüsusi sistemlər və tənzimləmələr").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { onOpenSettings() } label: {
                            Image(systemName: "gearshape.fill").font(.title3)
                        }
                    }

                    // 1. Park Charge Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Park Şarj (Mühərriklə Şarj)", systemImage: "bolt.batteryblock.fill")
                                .font(.headline)
                            Spacer()
                            if parkChargeActive {
                                Text("Aktiv").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.green.opacity(0.18), in: Capsule()).foregroundStyle(.green)
                            }
                        }

                        if online && !parkChargeActive && (0...100).contains(t.batterySoc) && t.batterySoc >= targetSoc {
                            Text("Batareya (\(t.batterySoc)%) seçilmiş hədəfdən (\(targetSoc)%) yüksəkdir — daha yüksək hədəf seçin.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        HStack {
                            Text("Hədəf SOC").font(.caption.weight(.bold))
                            Spacer()
                            Text("\(targetSoc)%").font(.headline.weight(.bold)).foregroundStyle(.tint)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(min(max(targetSoc, 15), 80)) },
                                set: { targetSoc = min(max(Int(($0 / 5.0).rounded()) * 5, 15), 80) }
                            ),
                            in: 15...80,
                            step: 5
                        ) { editing in
                            isTargetSocDragging = editing
                            if !editing && parkChargeActive && online {
                                viewModel.updateParkChargeTargetSoc(targetSoc)
                            }
                        }
                        .disabled(!online || viewModel.parkChargeStarting)

                        HStack(spacing: 8) {
                            ForEach([30, 50, 70, 80], id: \.self) { pct in
                                Button("\(pct)%") {
                                    targetSoc = pct
                                    if parkChargeActive && online {
                                        viewModel.updateParkChargeTargetSoc(pct)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(targetSoc == pct ? .accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                viewModel.startParkCharge(targetSoc: targetSoc)
                            } label: {
                                Text(parkChargeActive ? "Hədəfi yenilə (\(targetSoc)%)" : "Mühərriki işə sal və şarj et (\(targetSoc)%)")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 42)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!online || viewModel.parkChargeStarting)

                            if parkChargeActive || viewModel.parkChargeStarting {
                                Button("Dayandır") {
                                    viewModel.stopParkCharge(stopEngine: false)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // 2. Safety & Mühafizə
                    Toggle(isOn: Binding(
                        get: { online && t.safetyArmed },
                        set: { _ in viewModel.toggleSafetyMode() }
                    )) {
                        Label("Mühafizə Rejimi (Qapı açıldıqda Xəbərdarlıq)", systemImage: "shield.checkered")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                    .disabled(!online)

                    // 3. Light Show
                    DisclosureGroup("İşıq Şousu və Musiqi Sinxronizasiyası") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Profil", selection: $lsProfile) {
                                Text("Musiqi").tag("BEAT_SYNC")
                                Text("Dairəvi dövri").tag("CIRCULAR_SWEEP")
                                Text("Zavod").tag("OEM_DANCE")
                                Text("Strob").tag("STROBE_VIP")
                                Text("Qarışıq").tag("MIXED_SHOW")
                            }
                            Picker("Səs çıxışı", selection: $lsRoute) {
                                Text("Salon + AVAS").tag("DUAL")
                                Text("Yalnız AVAS").tag("AVAS_ONLY")
                                Text("Salon").tag("CABIN_ONLY")
                                Text("Səssiz").tag("SILENT")
                            }
                            .pickerStyle(.segmented)

                            Toggle("Şüşələri az arala", isOn: $lsVentWindows)
                            Toggle("Faralar", isOn: $lsHeadlights)
                            Toggle("Uzaq işıq", isOn: $lsHighBeams)
                            Toggle("Dönmə siqnalları", isOn: $lsTurnSignals)
                            Toggle("Qabaritlər", isOn: $lsWidthLamps)

                            Text("Salon səs gücü: \(Int(lsCabinVol * 100))%").font(.caption)
                            Slider(value: $lsCabinVol, in: 0...1) { editing in
                                isCabinVolDragging = editing
                                if !editing && online {
                                    viewModel.setAgentSettings(["lsCabinVolumePercent": Int(lsCabinVol * 100)])
                                }
                            }
                            .disabled(!online)

                            Text("AVAS çöl səs gücü: \(Int(lsAvasVol * 100))%").font(.caption)
                            Slider(value: $lsAvasVol, in: 0...1) { editing in
                                isAvasVolDragging = editing
                                if !editing && online {
                                    viewModel.setAgentSettings(["lsAvasVolumePercent": Int(lsAvasVol * 100)])
                                }
                            }
                            .disabled(!online)

                            Button {
                                if t.lightShowActive {
                                    viewModel.stopLightShow()
                                } else {
                                    viewModel.startLightShow(
                                        profile: lsProfile, audioRoute: lsRoute, track: lsTrack,
                                        cabinVolume: lsCabinVol, avasVolume: lsAvasVol,
                                        ventWindows: lsVentWindows, headlights: lsHeadlights,
                                        highBeams: lsHighBeams, turnSignals: lsTurnSignals, widthLamps: lsWidthLamps
                                    )
                                }
                            } label: {
                                Text(t.lightShowActive ? "İşıq Şousunu Dayandır" : "İşıq Şousunu Başlat")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(t.lightShowActive ? .red : .accentColor)
                            .disabled(!online && !t.lightShowActive)
                        }
                        .padding(.top, 8)
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // 4. Engine Sound
                    DisclosureGroup("Xarici AVAS Mühərrik Səsi") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Mühərrik səsi aktivdir", isOn: Binding(
                                get: { online && t.engineSoundEnabled },
                                set: { viewModel.setEngineSound(enabled: $0) }
                            ))
                            .disabled(!online)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(engineProfiles, id: \.code) { prof in
                                        let sel = online && t.engineSoundProfile == prof.code
                                        Button(prof.label) {
                                            viewModel.setEngineSound(enabled: true, profile: prof.code)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(sel ? .orange : .gray.opacity(0.4))
                                        .disabled(!online)
                                    }
                                }
                            }

                            Button("Qaz ver — AVAS sınağı (6500 RPM)") {
                                viewModel.revEngineSound()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .frame(maxWidth: .infinity)
                            .disabled(!online)
                        }
                        .padding(.top, 8)
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // 5. External Megaphone & Sound Signals
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Xarici meqafon və səs siqnalları").font(.headline)

                        Text("AVAS və meqafon səs səviyyəsi").font(.caption.weight(.bold))
                        Picker("Səviyyə", selection: Binding(
                            get: { viewModel.avasVolumeTier },
                            set: { viewModel.setAvasVolumeTier($0) }
                        )) {
                            Text("Zəif").tag("weak")
                            Text("Normal").tag("normal")
                            Text("Çox güclü").tag("strong")
                        }
                        .pickerStyle(.segmented)
                        .disabled(!online)

                        Slider(value: $draftAvasVolume, in: 0.1...3.0) { editing in
                            isAvasVolumeDragging = editing
                            if !editing && online {
                                viewModel.setAvasVolume(draftAvasVolume)
                            }
                        }
                        .disabled(!online)

                        // Live Hold-to-Talk Megaphone
                        HStack {
                            Image(systemName: "megaphone.fill")
                            Text(viewModel.isTalking ? "Canlı yayım aktivdir (Buraxın)" : "Basıb saxlayıb danışın (Meqafon)")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(viewModel.isTalking ? Color.red : (online ? Color.accentColor : Color.secondary.opacity(0.3)), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard online, !viewModel.isTalking else { return }
                                    viewModel.startLiveTalk()
                                }
                                .onEnded { _ in
                                    if viewModel.isTalking { viewModel.stopLiveTalk() }
                                }
                        )
                        .onDisappear {
                            if viewModel.isTalking { viewModel.stopLiveTalk() }
                            if holdingSoundId != nil {
                                holdingSoundId = nil
                                viewModel.stopAvasSound()
                            }
                        }

                        // Sound Signal Category Tabs
                        Picker("Kateqoriya", selection: $selectedSoundTab) {
                            ForEach(soundCategories, id: \.key) { cat in
                                Text(cat.title).tag(cat.key)
                            }
                        }
                        .pickerStyle(.segmented)

                        let currentItems = soundCategories.first(where: { $0.key == selectedSoundTab })?.items ?? []
                        ForEach(currentItems) { sound in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sound.name).font(.subheadline.weight(.semibold))
                                    Text(sound.desc).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Çal") {
                                    holdingSoundId = sound.id
                                    viewModel.playAvasSound(sound.id, loop: false)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!online)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            holdingSoundId = nil
                            viewModel.stopAvasSound()
                        } label: {
                            Label("Siqnal səsini dayandır", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(!online)
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                    // 6. GPS Locator Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avtomobilin məkanı (GPS)").font(.subheadline.weight(.bold))
                            let hasGps = t.latitude.isFinite && t.longitude.isFinite && t.locationEpoch > 0
                            Text(hasGps ? String(format: "%.5f, %.5f", t.latitude, t.longitude) : "GPS koordinatları gözlənilir")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            viewModel.openCarMap()
                        } label: {
                            Label("Xəritə", systemImage: "map.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!(t.latitude.isFinite && t.longitude.isFinite && t.locationEpoch > 0))
                    }
                    .padding(14)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal)
                .padding(.bottom, 84)
            }
            .onAppear {
                draftAvasVolume = viewModel.avasVolume
            }
            .onChange(of: t.saveTargetSoc) { _, soc in
                if !isTargetSocDragging && (15...80).contains(soc) { targetSoc = soc }
            }
            .onChange(of: t.agentLsCabinVolumePct) { _, pct in
                if !isCabinVolDragging && (0...100).contains(pct) { lsCabinVol = Float(pct) / 100.0 }
            }
            .onChange(of: t.agentLsAvasVolumePct) { _, pct in
                if !isAvasVolDragging && (0...100).contains(pct) { lsAvasVol = Float(pct) / 100.0 }
            }
            .onChange(of: viewModel.avasVolume) { _, v in
                if !isAvasVolumeDragging { draftAvasVolume = v }
            }
        }
    }
}
