import Foundation
import AVFoundation

/// Handles low-latency cabin PCM audio playback and 16kHz microphone capture for AVAS live megaphone.
final class CabinAudioManager {
    private let playLock = NSLock()
    private var playEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var activeSampleRate: Int = 0

    private let recLock = NSLock()
    private var recordEngine: AVAudioEngine?
    private var isRecording = false

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func playPcmChunk(_ pcm16Mono: Data, sampleRate: Int) {
        let rate = min(max(sampleRate, 8000), 48000)
        guard pcm16Mono.count >= 2 else { return }

        playLock.lock()
        defer { playLock.unlock() }

        if playEngine == nil || playerNode == nil || activeSampleRate != rate {
            stopPlaybackLocked()
            configureAudioSessionForVoice()

            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false) else {
                return
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
                node.play()
                playEngine = engine
                playerNode = node
                activeSampleRate = rate
            } catch {
                return
            }
        }

        guard let node = playerNode,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false) else {
            return
        }
        let sampleCount = pcm16Mono.count / 2
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let floatChannel = buffer.floatChannelData?[0] else { return }

        pcm16Mono.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Int16(littleEndian: int16Ptr[i])
                floatChannel[i] = Float(sample) / 32768.0
            }
        }

        if !node.isPlaying {
            node.play()
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stopPlayback() {
        playLock.lock()
        stopPlaybackLocked()
        playLock.unlock()
    }

    private func stopPlaybackLocked() {
        playerNode?.stop()
        playEngine?.stop()
        playEngine = nil
        playerNode = nil
        activeSampleRate = 0
    }

    func startMicCapture(onChunk: @escaping (Data) -> Void, onError: @escaping (String) -> Void) {
        recLock.lock()
        stopMicCaptureLocked()
        configureAudioSessionForVoice()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            recLock.unlock()
            onError("Mikrofon formatı başlana bilmədi")
            return
        }

        isRecording = true
        recordEngine = engine
        recLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { buffer, _ in
            let ratio = targetFormat.sampleRate / hwFormat.sampleRate
            let outCapacity = max(160, AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

            var inputConsumed = false
            var convError: NSError?
            let status = converter.convert(to: convertedBuffer, error: &convError) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if (status == .haveData || status == .inputRanDry), convertedBuffer.frameLength > 0,
               let int16Ptr = convertedBuffer.int16ChannelData?[0] {
                let byteCount = Int(convertedBuffer.frameLength) * 2
                let data = Data(bytes: int16Ptr, count: byteCount)
                onChunk(data)
            }
        }

        do {
            try engine.start()
        } catch {
            stopMicCapture()
            onError("Mikrofon açılmadı: \(error.localizedDescription)")
        }
    }

    func stopMicCapture() {
        recLock.lock()
        stopMicCaptureLocked()
        recLock.unlock()
    }

    private func stopMicCaptureLocked() {
        isRecording = false
        recordEngine?.inputNode.removeTap(onBus: 0)
        recordEngine?.stop()
        recordEngine = nil
    }

    private func configureAudioSessionForVoice() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setPreferredSampleRate(16000)
        try? session.setActive(true)
    }
}
