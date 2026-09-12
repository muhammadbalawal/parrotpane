import AVFoundation
import Cocoa

/// Hosts the mirrored pane. The full source window is rendered into a clipped host layer and
/// offset so that only the selected pane is visible, which keeps re-cropping to a layer
/// geometry change rather than a capture reconfiguration.
private final class MirrorContentView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    private var sourceSize = CGSize.zero
    private var crop = CGRect.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.masksToBounds = true
        host.isGeometryFlipped = true
        host.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resize
        host.addSublayer(displayLayer)
        layer = host
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        applyGeometry()
    }

    func configure(sourceSize: CGSize, crop: CGRect) {
        self.sourceSize = sourceSize
        self.crop = crop
        applyGeometry()
    }

    private func applyGeometry() {
        guard crop.width > 0, crop.height > 0, sourceSize.width > 0, bounds.width > 0 else { return }
        let scale = min(bounds.width / crop.width, bounds.height / crop.height)
        let insetX = (bounds.width - crop.width * scale) / 2
        let insetY = (bounds.height - crop.height * scale) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = CGRect(x: insetX - crop.minX * scale,
                                    y: insetY - crop.minY * scale,
                                    width: sourceSize.width * scale,
                                    height: sourceSize.height * scale)
        CATransaction.commit()
    }
}

final class MirrorWindow {
    private let window: NSWindow
    private let contentView: MirrorContentView
    private var appliedAspect: CGFloat = 0

    init(title: String) {
        contentView = MirrorContentView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    func present(cropSize: CGSize) {
        appliedAspect = cropSize.width / cropSize.height
        window.contentAspectRatio = NSSize(width: cropSize.width, height: cropSize.height)
        window.setContentSize(fittedSize(for: cropSize))
        window.center()
        window.orderFrontRegardless()

    }

    func configure(sourceSize: CGSize, crop: CGRect) {
        contentView.configure(sourceSize: sourceSize, crop: crop)
        window.contentAspectRatio = NSSize(width: crop.width, height: crop.height)

        let aspect = crop.width / crop.height
        guard abs(aspect - appliedAspect) > 0.01 else { return }
        appliedAspect = aspect
        window.setContentSize(fittedSize(for: crop.size))
    }

    private func fittedSize(for cropSize: CGSize) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let limit = min(1,
                        min(visible.width * 0.8 / cropSize.width,
                            visible.height * 0.8 / cropSize.height))
        return NSSize(width: (cropSize.width * limit).rounded(),
                      height: (cropSize.height * limit).rounded())
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        let renderer = contentView.displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData else { return }
        renderer.enqueue(sampleBuffer)
    }

    func onClose(_ handler: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in handler() }
    }
}
