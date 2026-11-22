import SwiftUI
import AVFoundation

struct RegistrationView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedModel = "EADO PHEV"
    @State private var selectedYear = "2025"
    @State private var vinInput = ""
    @State private var selectedColor = "Yaş asfalt"
    @State private var plateRaw = ""
    @State private var errorMsg: String?

    let onCompleted: () -> Void
    let onBack: (() -> Void)?

    var formattedPlate: String {
        let clean = plateRaw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(7)
        var out = ""
        for (i, ch) in clean.enumerated() {
            if i == 2 || i == 4 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sahibinin məlumatları") {
                    TextField("Ad", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Soyad", text: $lastName)
                        .textContentType(.familyName)
                }

                Section("Avtomobil məlumatları") {
                    Picker("Model", selection: $selectedModel) {
                        Text("Changan EADO PHEV").tag("EADO PHEV")
                        Text("Changan Qiyuan A05").tag("Qiyuan A05")
                    }

                    Picker("Buraxılış ili", selection: $selectedYear) {
                        Text("2025").tag("2025")
                        Text("2024").tag("2024")
                    }
                    .pickerStyle(.segmented)

                    Picker("Rəng", selection: $selectedColor) {
                        Text("Yaş asfalt").tag("Yaş asfalt")
                        Text("Ağ").tag("Ağ")
                    }
                    .pickerStyle(.segmented)

                    TextField("VIN kod (17 simvol)", text: $vinInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: vinInput) { _, val in
                            let sanitized = val.uppercased()
                                .replacingOccurrences(of: "O", with: "0")
                                .replacingOccurrences(of: "Q", with: "0")
                                .replacingOccurrences(of: "I", with: "1")
                                .filter { $0.isLetter || $0.isNumber }
                            vinInput = String(sanitized.prefix(17))
                        }

                    TextField("Dövlət nişanı (Məs: 99AB123)", text: $plateRaw)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: plateRaw) { _, val in
                            let clean = val.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(7)
                            plateRaw = String(clean)
                        }

                    if !plateRaw.isEmpty {
                        LabeledContent("Formatlanmış nişan", value: formattedPlate)
                    }
                }

                if let errorMsg {
                    Section {
                        Text(errorMsg)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        if viewModel.saveRegistration(
                            firstName: firstName,
                            lastName: lastName,
                            model: selectedModel,
                            year: selectedYear,
                            vinInput: vinInput,
                            color: selectedColor,
                            plate: formattedPlate
                        ) {
                            errorMsg = nil
                            onCompleted()
                        } else {
                            errorMsg = viewModel.toastMessage
                        }
                    } label: {
                        Text("Qeydiyyatı tamamla")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Avtomobil qeydiyyatı")
            .toolbar {
                if let onBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Geri", action: onBack)
                    }
                }
            }
            .onAppear {
                firstName = viewModel.userFirstName
                lastName = viewModel.userLastName
                selectedModel = viewModel.carModel.isEmpty ? "EADO PHEV" : viewModel.carModel
                selectedYear = (viewModel.carYear == "2024" || viewModel.carYear == "2025") ? viewModel.carYear : "2025"
                vinInput = (viewModel.vin != "QA_OFFLINE_NO_VEHICLE") ? viewModel.vin : ""
                selectedColor = viewModel.carColor.isEmpty ? "Yaş asfalt" : viewModel.carColor
                plateRaw = viewModel.carPlate.filter { $0.isLetter || $0.isNumber }
            }
        }
    }
}

struct VehiclePairingView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel
    @State private var showQrScanner = false
    @State private var pinInput = ""
    @State private var isPairing = false
    @State private var errorMessage: String?

    let onCompleted: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Changan \(viewModel.carModel) \(viewModel.carYear)")
                                    .font(.headline)
                                Text("Dövlət nişanı: \(viewModel.carPlate)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                            Spacer()
                            Text("Qeydiyyat hazırdır")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.green)
                        }
                        Divider()
                        LabeledContent("VIN kod", value: viewModel.vin)
                            .font(.caption.monospaced())
                    }
                    .padding()
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                    VStack(spacing: 14) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 46))
                            .foregroundStyle(.tint)
                        Text("Avtomobil monitorundakı QR kodu skan edin")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("Avtomobilinizin monitorunda 'Mobil tətbiqi qoş' və ya 'Aktivləşdir' düyməsinə toxunun və ekranda çıxan QR kodu skan edin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            errorMessage = nil
                            showQrScanner = true
                        } label: {
                            Label("QR Kodu Skan Et", systemImage: "camera.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPairing)
                    }
                    .padding(18)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Alternativ: 6-rəqəmli təhlükəsizlik PİN kodu")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            TextField("6-rəqəmli kod", text: $pinInput)
                                .keyboardType(.numberPad)
                                .font(.title3.monospacedDigit())
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: pinInput) { _, val in
                                    pinInput = String(val.filter(\.isNumber).prefix(6))
                                }

                            Button("Təsdiqlə") {
                                isPairing = true
                                errorMessage = nil
                                viewModel.completeVehiclePairing(pin: pinInput) { ok, err in
                                    isPairing = false
                                    if ok { onCompleted() }
                                    else { errorMessage = err }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isPairing || pinInput.count != 6)
                        }
                    }
                    .padding()
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                    if isPairing {
                        ProgressView("Avtomobillə şifrəli təsdiq aparılır…")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Avtomobili aktivləşdirmə")
            .toolbar {
                if let onBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Geri", action: onBack)
                    }
                }
            }
            .sheet(isPresented: $showQrScanner) {
                QrCameraScannerSheet { scannedCode in
                    showQrScanner = false
                    isPairing = true
                    errorMessage = nil
                    viewModel.completeVehiclePairingWithQr(scannedCode) { ok, err in
                        isPairing = false
                        if ok { onCompleted() }
                        else { errorMessage = err ?? viewModel.toastMessage }
                    }
                }
            }
        }
    }
}

private struct QrCameraScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCodeScanned: (String) -> Void

    var body: some View {
        NavigationStack {
            QrScannerRepresentable(onCodeScanned: onCodeScanned)
                .ignoresSafeArea()
                .navigationTitle("QR Kod Skaneri")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Bağla") { dismiss() }
                    }
                }
        }
    }
}

private struct QrScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QrScannerViewController {
        let vc = QrScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QrScannerViewController, context: Context) {}
}

private final class QrScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !handled,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue, !code.isEmpty else {
            return
        }
        handled = true
        session.stopRunning()
        onCodeScanned?(code)
    }
}
