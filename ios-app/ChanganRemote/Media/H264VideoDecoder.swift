import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Hardware-accelerated Annex-B H.264 decoder feeding AVSampleBufferDisplayLayer.
final class H264VideoDecoder {
    private let lock = NSLock()
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var formatDescription: CMVideoFormatDescription?
    private var lastSps: Data?
    private var lastPps: Data?
    private var awaitingKeyFrame = true
    private var pendingConfigData: Data?

    func attach(layer: AVSampleBufferDisplayLayer) {
        lock.lock()
        displayLayer = layer
        lock.unlock()
        DispatchQueue.main.async {
            if layer.status == .failed {
                layer.flushAndRemoveImage()
            }
        }
    }

    func detach(layer: AVSampleBufferDisplayLayer? = nil) {
        lock.lock()
        if layer == nil || displayLayer === layer {
            displayLayer = nil
        }
        awaitingKeyFrame = true
        lock.unlock()
    }

    func waitForKeyframe() {
        lock.lock()
        awaitingKeyFrame = true
        lock.unlock()
    }

    func isAwaitingKeyFrame() -> Bool {
        lock.lock()
        let v = awaitingKeyFrame
        lock.unlock()
        return v
    }

    func reset() {
        lock.lock()
        formatDescription = nil
        lastSps = nil
        lastPps = nil
        pendingConfigData = nil
        awaitingKeyFrame = true
        let layer = displayLayer
        lock.unlock()

        if let layer {
            DispatchQueue.main.async {
                layer.flushAndRemoveImage()
            }
        }
    }

    @discardableResult
    func submitFrame(
        frameBytes: Data,
        configBytes: Data?,
        isKeyFrame: Bool,
        ptsUs: Int64
    ) -> Bool {
        lock.lock()
        if let configBytes, !configBytes.isEmpty {
            pendingConfigData = configBytes
            extractParameterSets(from: configBytes)
        }
        extractParameterSets(from: frameBytes)

        if awaitingKeyFrame {
            if !isKeyFrame {
                lock.unlock()
                return false
            }
            awaitingKeyFrame = false
        }

        if formatDescription == nil, let cfg = pendingConfigData {
            extractParameterSets(from: cfg)
        }

        guard let desc = formatDescription, let layer = displayLayer else {
            lock.unlock()
            return false
        }
        lock.unlock()

        let sliceNals = splitAnnexBNalUnits(frameBytes).filter { nal in
            guard let first = nal.first else { return false }
            let nalType = first & 0x1F
            return nalType != 7 && nalType != 8
        }
        guard !sliceNals.isEmpty else { return false }

        var avccData = Data()
        for nal in sliceNals {
            var bigLen = CFSwapInt32HostToBig(UInt32(nal.count))
            withUnsafeBytes(of: &bigLen) { avccData.append(contentsOf: $0) }
            avccData.append(nal)
        }

        var blockBuffer: CMBlockBuffer?
        let status1 = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status1 == kCMBlockBufferNoErr, let blockBuffer else { return false }

        let status2 = avccData.withUnsafeBytes { rawBuf -> OSStatus in
            guard let base = rawBuf.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        guard status2 == kCMBlockBufferNoErr else { return false }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: max(0, ptsUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = avccData.count
        var sampleBuffer: CMSampleBuffer?
        let status3 = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: desc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status3 == noErr, let sampleBuffer else { return false }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let rawPtr = CFArrayGetValueAtIndex(attachments, 0) {
            let dict = Unmanaged<CFMutableDictionary>.fromOpaque(rawPtr).takeUnretainedValue()
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        DispatchQueue.main.async {
            if layer.status == .failed {
                layer.flush()
            }
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sampleBuffer)
            } else {
                layer.flush()
                layer.enqueue(sampleBuffer)
            }
        }
        return true
    }

    private func extractParameterSets(from data: Data) {
        var foundSps: Data?
        var foundPps: Data?
        for nal in splitAnnexBNalUnits(data) {
            guard let first = nal.first else { continue }
            let nalType = first & 0x1F
            if nalType == 7 { foundSps = nal }
            else if nalType == 8 { foundPps = nal }
        }
        let sps = foundSps ?? lastSps
        let pps = foundPps ?? lastPps
        guard let sps, let pps else { return }
        if sps == lastSps && pps == lastPps && formatDescription != nil { return }

        var newDesc: CMVideoFormatDescription?
        let createdStatus: OSStatus = sps.withUnsafeBytes { spsBuf in
            pps.withUnsafeBytes { ppsBuf in
                guard let spsPtr = spsBuf.bindMemory(to: UInt8.self).baseAddress,
                      let ppsPtr = ppsBuf.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }
                let ptrs: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let sizes: [Int] = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: ptrs,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newDesc
                )
            }
        }
        if createdStatus == noErr, let newDesc {
            lastSps = sps
            lastPps = pps
            formatDescription = newDesc
        }
    }

    private func splitAnnexBNalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        let n = bytes.count
        var ranges: [(Int, Int)] = []
        var i = 0
        var nalStart: Int? = nil

        while i < n {
            if i + 3 < n && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                if let start = nalStart, start < i { ranges.append((start, i)) }
                i += 4
                nalStart = i
            } else if i + 2 < n && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                if let start = nalStart, start < i { ranges.append((start, i)) }
                i += 3
                nalStart = i
            } else {
                i += 1
            }
        }
        if let start = nalStart, start < n {
            ranges.append((start, n))
        }
        if ranges.isEmpty && !bytes.isEmpty {
            return [data]
        }
        return ranges.map { Data(bytes[$0.0..<$0.1]) }
    }
}
