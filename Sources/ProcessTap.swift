import AVFoundation
import CoreAudio
import Foundation

/// Captures audio produced by a specific set of processes using a Core Audio process tap.
/// Unlike ScreenCaptureKit's per-application filters, this reaches helper processes such as
/// the Electron audio service, which is where browser sound is actually produced.
final class ProcessTap {
    struct Configuration {
        var processObjectIDs: [AudioObjectID]
        var mutesSource: Bool
    }

    let format: AVAudioFormat

    private let tapUUID: UUID
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false

    init(configuration: Configuration) throws {
        guard !configuration.processObjectIDs.isEmpty else { throw ParrotPaneError.noAudioProcesses }

        tapUUID = UUID()
        let description = CATapDescription(stereoMixdownOfProcesses: configuration.processObjectIDs)
        description.uuid = tapUUID
        description.name = "ParrotPane"
        description.isPrivate = true
        description.muteBehavior = configuration.mutesSource ? .muted : .unmuted

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioError.check(AudioHardwareCreateProcessTap(description, &createdTap), "create process tap")
        tapID = createdTap

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try CoreAudioError.check(
            AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &streamDescription),
            "read tap format")

        guard let resolved = AVAudioFormat(streamDescription: &streamDescription) else {
            throw ParrotPaneError.unsupportedAudioFormat
        }
        format = resolved

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ParrotPane Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUUID.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var createdAggregate = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioError.check(
            AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &createdAggregate),
            "create aggregate device")
        aggregateID = createdAggregate
    }

    deinit { teardown() }

    func start(handler: @escaping (UnsafePointer<AudioBufferList>) -> Void) throws {
        var procID: AudioDeviceIOProcID?
        try CoreAudioError.check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, _, _ in
                handler(input)
            },
            "install audio callback")
        ioProcID = procID
        try CoreAudioError.check(AudioDeviceStart(aggregateID, procID), "start tap device")
        running = true
    }

    func stop() { teardown() }

    private func teardown() {
        if running, let procID = ioProcID {
            AudioDeviceStop(aggregateID, procID)
            running = false
        }
        if let procID = ioProcID {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
