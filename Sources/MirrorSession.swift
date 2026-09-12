import Cocoa
import CoreAudio
import ScreenCaptureKit

final class MirrorSession {
    struct Options {
        var frameRate: Int
        var audioProcesses: [AudioProcess]
        var mutesSource: Bool
    }

    private let identity: PaneIdentity
    private let options: Options
    private let mirrorWindow: MirrorWindow

    private var capture: WindowMirror?
    private var tap: ProcessTap?
    private var relay: AudioRelay?
    private var follow: Timer?
    private var lastSourceSize = CGSize.zero
    private var lastCrop = CGRect.zero

    init(pane: TerminalPane, options: Options) {
        self.identity = pane.identity
        self.options = options
        self.mirrorWindow = MirrorWindow(title: "ParrotPane")
    }

    func start() async throws {
        let pane = try GhosttyPanes.pane(matching: identity)
        let window = try await SCShareableContent.ghosttyWindow(containing: CGPoint(x: pane.frame.midX, y: pane.frame.midY))
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        await MainActor.run {
            mirrorWindow.present(cropSize: pane.windowRelativeFrame.size)
            mirrorWindow.configure(sourceSize: window.frame.size, crop: pane.windowRelativeFrame)
            mirrorWindow.onClose { NSApp.terminate(nil) }
        }
        lastSourceSize = window.frame.size
        lastCrop = pane.windowRelativeFrame

        let capture = WindowMirror(window: window, scale: scale, frameRate: options.frameRate) { [weak self] buffer in
            self?.mirrorWindow.enqueue(buffer)
        }
        try await capture.start()
        self.capture = capture

        try startAudio()
        await MainActor.run { startFollowing() }
    }

    func stop() {
        follow?.invalidate()
        follow = nil
        tap?.stop()
        relay?.stop()
        let capture = self.capture
        self.capture = nil
        Task { await capture?.stop() }
    }

    private func startAudio() throws {
        guard !options.audioProcesses.isEmpty else { return }
        let tap = try ProcessTap(configuration: .init(
            processObjectIDs: options.audioProcesses.map(\.objectID),
            mutesSource: options.mutesSource))
        let relay = try AudioRelay(tapFormat: tap.format)
        try relay.start()
        try tap.start { [weak relay] bufferList in relay?.receive(bufferList) }
        self.tap = tap
        self.relay = relay
    }

    private func startFollowing() {
        follow = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshGeometry()
        }
    }

    private func refreshGeometry() {
        guard let pane = try? GhosttyPanes.pane(matching: identity) else { return }
        let crop = pane.windowRelativeFrame
        let sourceSize = pane.windowFrame.size
        guard crop != lastCrop || sourceSize != lastSourceSize else { return }

        if sourceSize != lastSourceSize {
            Task { [weak self] in
                guard let self,
                      let window = try? await SCShareableContent.ghosttyWindow(
                        containing: CGPoint(x: pane.frame.midX, y: pane.frame.midY))
                else { return }
                await self.capture?.resize(to: window)
            }
        }

        lastCrop = crop
        lastSourceSize = sourceSize
        mirrorWindow.configure(sourceSize: sourceSize, crop: crop)
    }
}
