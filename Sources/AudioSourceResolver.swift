import Cocoa
import CoreAudio
import Darwin

/// Resolves a user-supplied audio source into the CoreAudio process objects to tap.
/// Matching is done on each process's executable path rather than a bundle identifier,
/// because Electron and Chromium emit sound from helper processes whose bundle identity
/// belongs to the framework rather than the application.
enum AudioSourceResolver {
    static let defaultMatch = "terminal-browser"

    static func processObjectIDs(for reference: String?) throws -> [AudioProcess] {
        let needle = (reference ?? defaultMatch).lowercased()

        if let pid = pid_t(needle) {
            return try AudioProcesses.emittingAudio(under: pid)
        }

        let candidates = try AudioProcesses.all().filter { process in
            if process.bundleID.lowercased().contains(needle) { return true }
            guard let path = executablePath(of: process.pid) else { return false }
            return path.lowercased().contains(needle)
        }
        if !candidates.isEmpty { return candidates }

        guard let pid = runningApplicationPID(matching: needle) else { return [] }
        return try AudioProcesses.emittingAudio(under: pid)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func runningApplicationPID(matching needle: String) -> pid_t? {
        NSWorkspace.shared.runningApplications.first {
            ($0.localizedName?.lowercased().contains(needle) ?? false)
                || ($0.bundleIdentifier?.lowercased().contains(needle) ?? false)
        }?.processIdentifier
    }
}
