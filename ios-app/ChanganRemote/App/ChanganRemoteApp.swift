import SwiftUI

@main
struct ChanganRemoteApp: App {
    @StateObject private var viewModel = VehicleViewModel()
    @AppStorage("ui_theme_mode") private var themeMode: String = "SYSTEM"

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(
                    themeMode == "DARK" ? .dark : (themeMode == "LIGHT" ? .light : nil)
                )
        }
    }
}

private struct RootContentView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel
    @State private var showRegistrationEditor = false
    @State private var showPairingEditor = false

    var body: some View {
        Group {
            if !viewModel.isRegistered || showRegistrationEditor {
                RegistrationView(onCompleted: {
                    showRegistrationEditor = false
                }, onBack: showRegistrationEditor ? { showRegistrationEditor = false } : nil)
            } else if !viewModel.isVehiclePaired || showPairingEditor {
                VehiclePairingView(onCompleted: {
                    showPairingEditor = false
                }, onBack: showPairingEditor ? { showPairingEditor = false } : nil)
            } else {
                MainTabView(
                    onOpenRegistration: { showRegistrationEditor = true },
                    onOpenPairing: { showPairingEditor = true }
                )
            }
        }
        .alert(item: $viewModel.controlConfirmation) { req in
            Alert(
                title: Text(req.title),
                message: Text(req.message),
                primaryButton: .destructive(Text("Bəli, aç")) {
                    viewModel.confirmControlAction()
                },
                secondaryButton: .cancel(Text("Ləğv et")) {
                    viewModel.cancelControlConfirmation()
                }
            )
        }
    }
}
