import CoreMedia
import ScreenCaptureKit

/// Captures a single window with ScreenCaptureKit. The whole window is captured; selecting a
/// pane is done downstream by the view, so layout changes never restart the stream.
final class WindowMirror: NSObject, SCStreamOutput, SCStreamDelegate {
    private let frameHandler: (CMSampleBuffer) -> Void
    private let outputQueue = DispatchQueue(label: "dev.local.paneshare.capture")
    private var stream: SCStream?
    private var window: SCWindow
    private let scale: CGFloat
    private let frameRate: Int

    var sourceSize: CGSize { window.frame.size }

    init(window: SCWindow, scale: CGFloat, frameRate: Int, frameHandler: @escaping (CMSampleBuffer) -> Void) {
        self.window = window
        self.scale = scale
        self.frameRate = frameRate
        self.frameHandler = frameHandler
    }

    func start() async throws {
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                              configuration: makeConfiguration(),
                              delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    func resize(to window: SCWindow) async {
        self.window = window
        try? await stream?.updateConfiguration(makeConfiguration())
    }

    private func makeConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width * scale), 2)
        configuration.height = max(Int(window.frame.height * scale), 2)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.queueDepth = 6
        configuration.showsCursor = false
        configuration.scalesToFit = false
        return configuration
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }
        markForImmediateDisplay(sampleBuffer)
        DispatchQueue.main.async { self.frameHandler(sampleBuffer) }
    }

    private func markForImmediateDisplay(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
                as NSArray?,
              let first = attachments.firstObject as? NSMutableDictionary else { return }
        first[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true
    }
}

extension SCShareableContent {
    static func ghosttyWindow(containing point: CGPoint) async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == GhosttyPanes.bundleIdentifier && $0.windowLayer == 0
        }
        guard let match = candidates.first(where: { $0.frame.contains(point) }) else {
            throw ParrotPaneError.windowNotCapturable
        }
        return match
    }
}
