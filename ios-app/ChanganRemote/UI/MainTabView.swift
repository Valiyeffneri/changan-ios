import SwiftUI

enum MainTab: Int, CaseIterable {
    case home = 0
    case camera = 1
    case climate = 2
    case status = 3
    case more = 4

    var title: String {
        switch self {
        case .home: return "Əsas"
        case .camera: return "Kamera"
        case .climate: return "Klimat"
        case .status: return "Məlumat"
        case .more: return "Daha çox"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "car.fill"
        case .camera: return "video.fill"
        case .climate: return "thermometer.medium"
        case .status: return "chart.bar.doc.horizontal.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel
    @State private var selectedTab: MainTab = .home
    @State private var showSettings = false

    let onOpenRegistration: () -> Void
    let onOpenPairing: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                RemoteControlView(onOpenSettings: { showSettings = true })
                    .tabItem {
                        Label(MainTab.home.title, systemImage: MainTab.home.systemImage)
                    }
                    .tag(MainTab.home)

                CameraAudioView()
                    .tabItem {
                        Label(MainTab.camera.title, systemImage: MainTab.camera.systemImage)
                    }
                    .tag(MainTab.camera)

                ClimateView()
                    .tabItem {
                        Label(MainTab.climate.title, systemImage: MainTab.climate.systemImage)
                    }
                    .tag(MainTab.climate)

                VehicleStatusView()
                    .tabItem {
                        Label(MainTab.status.title, systemImage: MainTab.status.systemImage)
                    }
                    .tag(MainTab.status)

                MoreView(onOpenSettings: { showSettings = true })
                    .tabItem {
                        Label(MainTab.more.title, systemImage: MainTab.more.systemImage)
                    }
                    .tag(MainTab.more)
            }

            if let banner = viewModel.commandBanner {
                CommandStatusHud(banner: banner) {
                    viewModel.dismissCommandBanner()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 58)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.commandBanner?.id)
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(
                onOpenRegistration: {
                    showSettings = false
                    onOpenRegistration()
                },
                onOpenPairing: {
                    showSettings = false
                    onOpenPairing()
                }
            )
        }
    }
}

struct CommandStatusHud: View {
    let banner: CommandBannerState
    let onDismiss: () -> Void

    var accentColor: Color {
        switch banner.severity {
        case .pending: return .accentColor
        case .success: return Color(red: 0.06, green: 0.72, blue: 0.51)
        case .warning: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .error: return .red
        case .info: return .blue
        }
    }

    var iconName: String {
        switch banner.severity {
        case .pending: return "clock.arrow.circlepath"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if banner.severity == .pending {
                ProgressView()
                    .controlSize(.small)
                    .tint(accentColor)
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(accentColor)
                    .font(.system(size: 18, weight: .semibold))
            }

            Text(banner.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let channel = banner.channelLabel, !channel.isEmpty {
                Text(channel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            }

            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accentColor.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .onTapGesture {
            onDismiss()
        }
    }
}

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: VehicleViewModel
    @AppStorage("ui_theme_mode") private var themeMode: String = "SYSTEM"

    @State private var broker: String = ""
    @State private var vin: String = ""
    @State private var secret: String = ""
    @State private var revealSecret = false
    @State private var saveError: String?

    let onOpenRegistration: () -> Void
    let onOpenPairing: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Avtomobil və Sahibi") {
                    Button {
                        onOpenRegistration()
                    } label: {
                        HStack {
                            Image(systemName: "car.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                let fullName = "\(viewModel.userFirstName) \(viewModel.userLastName)".trimmingCharacters(in: .whitespaces)
                                Text(fullName.isEmpty ? "Avtomobil qeydiyyatı" : fullName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Changan \(viewModel.carModel) · \(viewModel.carPlate)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Dəyiş")
                                .font(.caption.weight(.semibold))
                        }
                    }

                    Button("QR / PİN ilə yenidən aktivləşdir") {
                        onOpenPairing()
                    }
                }

                Section("Görünüş") {
                    Picker("Tema rejimi", selection: $themeMode) {
                        Text("Sistem").tag("SYSTEM")
                        Text("Açıq").tag("LIGHT")
                        Text("Tünd").tag("DARK")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    let t = viewModel.telemetry
                    Button {
                        if t.standbyKeepalive { viewModel.setStandbyMode(false) }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(t.isConnected && !t.standbyKeepalive ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Klassik rejim (pultla oyanma)")
                                    .foregroundStyle(.primary)
                                Text("Avtomobil söndükdə bütün rabitə sönür və 12V akkumulyator qorunur.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if t.isConnected && !t.standbyKeepalive {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(!t.isConnected)

                    Button {
                        if !t.standbyKeepalive { viewModel.setStandbyMode(true) }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "icloud.fill")
                                .foregroundStyle(t.isConnected && t.standbyKeepalive ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("T-Box bulud rejimi (uzaqdan start)")
                                    .foregroundStyle(.primary)
                                Text("Avtomobil yuxuda olarkən 4G/Wi-Fi ilə pultsuz oyanma üçündür.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if t.isConnected && t.standbyKeepalive {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(!t.isConnected)
                } header: {
                    Text("Oyanma və enerji rejimi")
                }

                Section("Baş Qurğu Ayarları") {
                    let connected = viewModel.telemetry.isConnected
                    Toggle("Sürüşdə zavod AVAS səsini susdur", isOn: Binding(
                        get: { viewModel.telemetry.agentAutoMuteAvas ?? true },
                        set: { viewModel.setAgentSettings(["autoMuteAvas": $0]) }
                    ))
                    .disabled(!connected)

                    Toggle("Qapı kilid / açılış təsdiq səsi", isOn: Binding(
                        get: { viewModel.telemetry.agentLockChimeEnabled ?? true },
                        set: { viewModel.setAgentSettings(["lockChimeEnabled": $0]) }
                    ))
                    .disabled(!connected)

                    Toggle("Radioları avtomatik bərpa et", isOn: Binding(
                        get: { viewModel.telemetry.agentRadioRecovery ?? true },
                        set: { viewModel.setAgentSettings(["radioRecovery": $0]) }
                    ))
                    .disabled(!connected)

                    Toggle("Startda son klimat rejimlərini bərpa et", isOn: Binding(
                        get: { viewModel.telemetry.agentAutoClimate ?? false },
                        set: { viewModel.setAgentSettings(["autoClimate": $0]) }
                    ))
                    .disabled(!connected)
                }

                Section("Avtomobil Bağlantısı (MQTT)") {
                    TextField("MQTT broker ünvanı", text: $broker)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("VIN kod", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    HStack {
                        if revealSecret {
                            TextField("Gizli açar (HMAC)", text: $secret)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Gizli açar (HMAC)", text: $secret)
                        }
                        Button {
                            revealSecret.toggle()
                        } label: {
                            Image(systemName: revealSecret ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Özəl TLS hostname yoxlamasını keç", isOn: Binding(
                        get: { viewModel.allowInsecureCustomTls },
                        set: { viewModel.setAllowInsecureCustomTls($0) }
                    ))

                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        if viewModel.updateSettings(newBroker: broker, newVin: vin, newSecret: secret) {
                            saveError = nil
                            dismiss()
                        } else {
                            saveError = "Broker ünvanı (ssl://host:port), VIN və gizli açarı (min 16 simvol) yoxlayın."
                        }
                    } label: {
                        Label("Yadda saxla və qoşul", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Tənzimləmələr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bağla") { dismiss() }
                }
            }
            .onAppear {
                broker = viewModel.brokerUrl
                vin = viewModel.vin
                secret = viewModel.secretKey
            }
        }
    }
}
