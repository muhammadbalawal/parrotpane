import CoreAudio
import Foundation

struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
}

/// Enumerates the CoreAudio process objects that can be targeted by a process tap.
/// These include helper processes that ScreenCaptureKit does not expose.
enum AudioProcesses {
    static func all() throws -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var byteSize: UInt32 = 0
        try CoreAudioError.check(
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteSize),
            "read process object list size")

        var identifiers = [AudioObjectID](repeating: 0, count: Int(byteSize) / MemoryLayout<AudioObjectID>.size)
        try CoreAudioError.check(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteSize, &identifiers),
            "read process object list")

        return identifiers.compactMap { identifier in
            guard let pid = value(of: identifier, kAudioProcessPropertyPID, as: pid_t.self) else { return nil }
            let bundleID = string(of: identifier, kAudioProcessPropertyBundleID) ?? ""
            return AudioProcess(objectID: identifier, pid: pid, bundleID: bundleID)
        }
    }

    static func emittingAudio(under ancestor: pid_t) throws -> [AudioProcess] {
        try all().filter { ProcessTree.isDescendant($0.pid, of: ancestor) }
    }

    private static func value<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return nil }
        return buffer.pointee
    }

    private static func string(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr,
              let value = result?.takeRetainedValue() else { return nil }
        return value as String
    }
}

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let action: String
    var errorDescription: String? { "\(action) failed (OSStatus \(status))" }

    static func check(_ status: OSStatus, _ action: String) throws {
        guard status != noErr else { return }
        throw CoreAudioError(status: status, action: action)
    }
}
