import SwiftUI
import AVFoundation

struct CameraAudioView: View {
    @EnvironmentObject private var viewModel: VehicleViewModel

    @State private var selectedCameraId = "evs_front"
    @State private var isFullscreen = false
    @State private var zoomScale: CGFloat = 1.0

    private let cameraOptions: [(id: String, short: String, full: String)] = [
        ("evs_front", "Ön", "Ön kamera"),
        ("evs_rear", "Arxa", "Arxa kamera"),
        ("evs_left", "Sol", "Sol kamera"),
        ("evs_right", "Sağ", "Sağ kamera"),
        ("evs_all", "2×2", "2×2 (4 kamera)"),
        ("evs_360", "360°", "360° AVM")
    ]

    var body: some View {
        let t = viewModel.telemetry
        let online = t.isConnected
        let streaming = viewModel.isVideoStreaming
        let h264Active = viewModel.isH264VideoActive

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kamera və Salon Səsi")
                                .font(.title2.weight(.bold))
                            let sub = h264Active && viewModel.videoFps > 0
                                ? "Canlı H.264 · \(viewModel.videoWidth)×\(viewModel.videoHeight) · \(viewModel.videoFps) FPS"
                                : (streaming ? "Canlı yayım hazırlanır..." : "360° AVM və ətraf görünüş")
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if streaming { isFullscreen = true }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title3)
                        }
                        .disabled(!streaming)
                    }

                    // Camera Selector Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cameraOptions, id: \.id) { opt in
                                let selected = selectedCameraId == opt.id
                                Button {
                                    selectedCameraId = opt.id
                                    if streaming {
                                        viewModel.switchLiveCamera(opt.id)
                                    }
                                } label: {
                                    Text(opt.short)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(selected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Live Viewport
                    CameraViewport(
                        decoder: viewModel.h264Decoder,
                        image: viewModel.cameraImage,
                        isH264Active: h264Active,
                        isStreaming: streaming,
                        isLoading: viewModel.isCameraLoading,
                        aspectRatio: viewModel.videoAspectRatio,
                        zoomScale: $zoomScale
                    )
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(streaming ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25), lineWidth: 1.5)
                    )

                    // Stream & Snapshot Controls
                    HStack(spacing: 10) {
                        Button {
                            if streaming {
                                viewModel.stopLiveVideo()
                            } else {
                                viewModel.startLiveVideo(cameraId: selectedCameraId)
                            }
                        } label: {
                            Label(
                                streaming ? "Yayımı Dayandır" : "Canlı Yayımı Başlat",
                                systemImage: streaming ? "stop.circle.fill" : "play.circle.fill"
                            )
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(streaming ? .red : .accentColor)
                        .disabled(!online && !streaming)

                        Button {
                            viewModel.captureAndSaveHighResSnapshot(cameraId: selectedCameraId, fallbackImage: viewModel.cameraImage)
                        } label: {
                            if viewModel.isCameraLoading {
                                ProgressView()
                                    .frame(width: 46, height: 46)
                            } else {
                                Label("Çək", systemImage: "camera.shutter.button.fill")
                                    .font(.subheadline.weight(.bold))
                                    .frame(minHeight: 46)
                                    .padding(.horizontal, 12)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!online || viewModel.isCameraLoading)
                    }

                    // Cabin Audio Listener Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: viewModel.isCabinListening ? "ear.fill" : "mic.fill")
                                .font(.title2)
                                .foregroundStyle(viewModel.isCabinListening ? .green : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Salon səsini dinlə")
                                    .font(.headline)
                                Text(viewModel.isCabinListening ? "Canlı salon mikrofonu aktivdir" : "Avtomobil salonundan canlı audio axını")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(viewModel.isCabinListening ? "Dayandır" : "Dinlə") {
                                viewModel.toggleCabinAudioListening()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewModel.isCabinListening ? .red : .accentColor)
                            .disabled(!online && !viewModel.isCabinListening)
                        }
                    }
                    .padding(16)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal)
                .padding(.bottom, 84)
            }
            .onChange(of: streaming || viewModel.isCabinListening) { _, keepAwake in
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .fullScreenCover(isPresented: $isFullscreen) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    CameraViewport(
                        decoder: viewModel.h264Decoder,
                        image: viewModel.cameraImage,
                        isH264Active: h264Active,
                        isStreaming: streaming,
                        isLoading: viewModel.isCameraLoading,
                        aspectRatio: viewModel.videoAspectRatio,
                        zoomScale: $zoomScale
                    )
                    Button {
                        isFullscreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(20)
                    }
                }
            }
        }
    }
}

private struct CameraViewport: View {
    let decoder: H264VideoDecoder
    let image: UIImage?
    let isH264Active: Bool
    let isStreaming: Bool
    let isLoading: Bool
    let aspectRatio: CGFloat
    @Binding var zoomScale: CGFloat

    var body: some View {
        ZStack {
            Color.black

            if isH264Active {
                H264DisplayView(decoder: decoder)
                    .scaleEffect(zoomScale)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomScale)
            } else {
                VStack(spacing: 10) {
                    if isStreaming || isLoading {
                        ProgressView().tint(.white)
                        Text(isLoading ? "Orijinal kadr çəkilir..." : "Video axını qoşulur...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Image(systemName: "video.slash")
                            .font(.system(size: 38))
                            .foregroundStyle(.gray)
                        Text("Kamera görüntüsü yoxdur")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .aspectRatio(max(aspectRatio, 1.0), contentMode: .fit)
        .gesture(
            MagnifyGesture()
                .onChanged { val in
                    zoomScale = min(max(val.magnification, 1.0), 4.0)
                }
                .onEnded { _ in
                    if zoomScale < 1.1 { zoomScale = 1.0 }
                }
        )
    }
}

private struct H264DisplayView: UIViewRepresentable {
    let decoder: H264VideoDecoder

    final class PlayerLayerView: UIView {
        weak var decoder: H264VideoDecoder?
        override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
        var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.displayLayer.videoGravity = .resizeAspect
        view.decoder = decoder
        decoder.attach(layer: view.displayLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) {
        uiView.decoder?.detach(layer: uiView.displayLayer)
        uiView.displayLayer.flushAndRemoveImage()
    }
}
