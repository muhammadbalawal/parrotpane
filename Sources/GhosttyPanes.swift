import ApplicationServices
import Cocoa

struct PaneIdentity: Equatable {
    let windowIndex: Int
    let path: String
}

struct TerminalPane {
    let identity: PaneIdentity
    let windowTitle: String
    let windowFrame: CGRect
    let frame: CGRect
    let textLength: Int
    let firstLine: String
    let isFocused: Bool

    var path: String { identity.path }

    var windowRelativeFrame: CGRect {
        CGRect(x: frame.minX - windowFrame.minX,
               y: frame.minY - windowFrame.minY,
               width: frame.width,
               height: frame.height)
    }

    /// Panes rendering images through the Kitty graphics protocol carry almost no text,
    /// which separates a browser pane from a shell pane reliably enough to auto-select.
    var rendersGraphics: Bool { textLength < 8_000 && firstLine.isEmpty }
}

/// Reads Ghostty's split layout through the Accessibility API. This is the only interface
/// Ghostty offers that reports where a pane actually is; its IPC and AppleScript dictionary
/// expose identity but no geometry.
enum GhosttyPanes {
    static let bundleIdentifier = "com.mitchellh.ghostty"

    static func list(includingText: Bool = true) throws -> [TerminalPane] {
        guard AXIsProcessTrusted() else { throw ParrotPaneError.accessibilityDenied }
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first
        else { throw ParrotPaneError.ghosttyNotRunning }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else {
            throw ParrotPaneError.accessibilityDenied
        }

        var panes = [TerminalPane]()
        for (windowIndex, window) in windows.enumerated() {
            guard let windowFrame = frame(of: window), windowFrame.height > 120 else { continue }
            let title = (attribute(window, kAXTitleAttribute) as? String) ?? ""
            collect(window, path: "", windowIndex: windowIndex, windowTitle: title,
                    windowFrame: windowFrame, includingText: includingText, into: &panes)
        }
        return panes
    }

    static func focusedPane() throws -> TerminalPane? {
        try list(includingText: true).first { $0.isFocused }
    }

    static func pane(matching identity: PaneIdentity) throws -> TerminalPane {
        let panes = try list(includingText: false)
        guard let match = panes.first(where: { $0.identity == identity }) else {
            throw ParrotPaneError.paneNotFound(identity.path)
        }
        return match
    }

    private static func collect(_ element: AXUIElement, path: String, windowIndex: Int,
                                windowTitle: String, windowFrame: CGRect,
                                includingText: Bool, into panes: inout [TerminalPane]) {
        let role = attribute(element, kAXRoleAttribute) as? String

        if role == "AXTextArea" {
            guard let paneFrame = frame(of: element) else { return }
            let text = includingText ? (attribute(element, kAXValueAttribute) as? String ?? "") : ""
            panes.append(TerminalPane(
                identity: PaneIdentity(windowIndex: windowIndex, path: path.isEmpty ? "pane" : path),
                windowTitle: windowTitle,
                windowFrame: windowFrame,
                frame: paneFrame,
                textLength: text.count,
                firstLine: firstNonEmptyLine(of: text),
                isFocused: (attribute(element, kAXFocusedAttribute) as? Bool) ?? false))
            return
        }

        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children {
            let description = (attribute(child, kAXDescriptionAttribute) as? String) ?? ""
            let childPath: String
            if description.isEmpty || description.hasSuffix("divider") {
                childPath = path
            } else if path.isEmpty {
                childPath = description
            } else {
                childPath = "\(path) > \(description)"
            }
            collect(child, path: childPath, windowIndex: windowIndex, windowTitle: windowTitle,
                    windowFrame: windowFrame, includingText: includingText, into: &panes)
        }
    }

    private static func firstNonEmptyLine(of text: String) -> String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
