import AVFoundation
import Foundation

/// Plays tapped audio back through this process so that a screen-sharing client,
/// which captures audio per application, picks it up from ParrotPane.
final class AudioRelay {
    private let engine = AVAudioEngine()
    private let ring: AudioRingBuffer
    private let renderFormat: AVAudioFormat
    private let prerollFrames: Int
    private var sourceNode: AVAudioSourceNode?
    private var priming = true

    init(tapFormat: AVAudioFormat) throws {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: tapFormat.sampleRate,
            channels: max(tapFormat.channelCount, 1))
        else { throw ParrotPaneError.unsupportedAudioFormat }

        renderFormat = format
        prerollFrames = Int(format.sampleRate * 0.02)
        ring = AudioRingBuffer(
            channelCount: Int(format.channelCount),
            capacity: Int(format.sampleRate * 0.5),
            maximumFill: Int(format.sampleRate * 0.06))
    }

    func start() throws {
        let node = AVAudioSourceNode(format: renderFormat) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if self.priming {
                if self.ring.available < self.prerollFrames {
                    for buffer in buffers {
                        if let base = buffer.mData { memset(base, 0, Int(buffer.mDataByteSize)) }
                    }
                    return noErr
                }
                self.priming = false
            }
            self.ring.read(into: buffers, frameCount: Int(frameCount))
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: renderFormat)
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        if let node = sourceNode { engine.detach(node) }
        sourceNode = nil
    }

    func receive(_ bufferList: UnsafePointer<AudioBufferList>) {
        ring.write(bufferList)
    }
}
