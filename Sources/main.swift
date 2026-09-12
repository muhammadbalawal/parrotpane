import Cocoa

private let captureFrameRate = 60

private func runList() throws {
    let panes = try GhosttyPanes.list()
    guard !panes.isEmpty else { throw ParrotPaneError.noPanes }

    var currentWindow = -1
    for (index, pane) in panes.enumerated() {
        if pane.identity.windowIndex != currentWindow {
            currentWindow = pane.identity.windowIndex
            let frame = pane.windowFrame
            print("\nWINDOW \"\(pane.windowTitle)\"  \(Int(frame.width))x\(Int(frame.height))")
        }
        let size = "\(Int(pane.frame.width))x\(Int(pane.frame.height))"
        let kind = pane.rendersGraphics ? "graphics" : "terminal"
        let detail = pane.firstLine.isEmpty ? "" : "  \(pane.firstLine.prefix(48))"
        print(String(format: "  [%d] %-26@ %-11@ %-9@%@",
                     index + 1, pane.path as NSString, size as NSString, kind as NSString, detail as NSString))
    }
    print("")
}

private func pane(at index: Int) throws -> TerminalPane {
    let panes = try GhosttyPanes.list()
    guard !panes.isEmpty else { throw ParrotPaneError.noPanes }
    guard index >= 1, index <= panes.count else { throw ParrotPaneError.paneNotFound("pane \(index)") }
    return panes[index - 1]
}

private func waitForBrowserPane(timeout: TimeInterval) throws -> TerminalPane {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let pane = try? GhosttyPanes.focusedPane(), pane.rendersGraphics { return pane }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
    throw ParrotPaneError.paneNeverAppeared
}

private func share(_ pane: TerminalPane) throws {
    let audioProcesses = (try? AudioSourceResolver.processObjectIDs(for: nil)) ?? []
    if audioProcesses.isEmpty {
        FileHandle.standardError.write("no audio source found; mirroring video only\n".data(using: .utf8)!)
    }

    print("mirroring \(pane.path) — \(Int(pane.frame.width))x\(Int(pane.frame.height))")
    print("share the \"ParrotPane\" window in your meeting app")

    let session = MirrorSession(pane: pane, options: .init(
        frameRate: captureFrameRate,
        audioProcesses: audioProcesses,
        mutesSource: true))

    Task {
        do { try await session.start() } catch {
            FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    NSApp.setActivationPolicy(.regular)
    NSApp.run()
    session.stop()
}

setvbuf(stdout, nil, _IOLBF, 0)

let application = NSApplication.shared

do {
    switch CommandLineOptions.parse(CommandLine.arguments).command {
    case .help:
        print(CommandLineOptions.usage)
    case .list:
        application.setActivationPolicy(.accessory)
        try runList()
    case .share(let index):
        try share(pane(at: index))
    case .waitForPane:
        try share(waitForBrowserPane(timeout: 30))
    }
} catch {
    FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
