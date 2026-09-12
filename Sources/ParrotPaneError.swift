import Foundation

enum ParrotPaneError: LocalizedError {
    case ghosttyNotRunning
    case accessibilityDenied
    case noPanes
    case paneNotFound(String)
    case windowNotCapturable
    case noAudioProcesses
    case unsupportedAudioFormat
    case paneNeverAppeared

    var errorDescription: String? {
        switch self {
        case .ghosttyNotRunning:
            return "Ghostty is not running."
        case .accessibilityDenied:
            return "Accessibility access is required to read Ghostty's pane layout.\n"
                 + "Grant it in System Settings > Privacy & Security > Accessibility."
        case .noPanes:
            return "No Ghostty panes found."
        case .paneNotFound(let reference):
            return "No pane matching \(reference). Run 'paneshare list' to see what is available."
        case .windowNotCapturable:
            return "Could not find the Ghostty window in the capturable window list."
        case .noAudioProcesses:
            return "No audio-producing process found for the requested source."
        case .unsupportedAudioFormat:
            return "The audio tap reported a format that could not be used for playback."
        case .paneNeverAppeared:
            return "The browser pane never appeared. Is terminal-browser installed and on PATH?"
        }
    }
}
