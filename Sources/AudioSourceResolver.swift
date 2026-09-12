import Cocoa
import CoreAudio

/// Resolves a user-supplied audio source into the CoreAudio process objects to tap.
/// Electron and Chromium emit sound from helper processes, so the whole process subtree
/// of the owning application is included rather than the application process alone.
enum AudioSourceResolver {
    static let defaultBundleIdentifier = "dev.zenbu.terminal-browser"

    static func processObjectIDs(for reference: String?) throws -> [AudioProcess] {
        guard let rootPID = try resolveRootPID(reference) else { return [] }
        return try AudioProcesses.emittingAudio(under: rootPID)
    }

    private static func resolveRootPID(_ reference: String?) throws -> pid_t? {
        guard let reference else { return runningPID(bundleIdentifier: defaultBundleIdentifier) }
        if let pid = pid_t(reference) { return pid }
        if let pid = runningPID(bundleIdentifier: reference) { return pid }
        let needle = reference.lowercased()
        let match = NSWorkspace.shared.runningApplications.first {
            ($0.localizedName?.lowercased().contains(needle) ?? false)
                || ($0.bundleIdentifier?.lowercased().contains(needle) ?? false)
        }
        return match?.processIdentifier
    }

    private static func runningPID(bundleIdentifier: String) -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .processIdentifier
    }
}
