import AVFoundation
import Foundation

/// Planar float ring buffer bridging the tap's real-time callback to the playback render thread.
final class AudioRingBuffer {
    private let channelCount: Int
    private let capacity: Int
    private let maximumFill: Int
    private var planes: [[Float]]
    private var writeIndex = 0
    private var readIndex = 0
    private var filled = 0
    private let lock = NSLock()

    init(channelCount: Int, capacity: Int, maximumFill: Int) {
        self.channelCount = max(channelCount, 1)
        self.capacity = capacity
        self.maximumFill = min(maximumFill, capacity)
        self.planes = Array(repeating: [Float](repeating: 0, count: capacity), count: self.channelCount)
    }

    var available: Int {
        lock.lock(); defer { lock.unlock() }
        return filled
    }

    func write(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard buffers.count > 0 else { return }

        let interleaved = buffers.count == 1 && channelCount > 1
        let frameCount: Int
        if interleaved {
            frameCount = Int(buffers[0].mDataByteSize) / (MemoryLayout<Float>.size * channelCount)
        } else {
            frameCount = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
        }
        guard frameCount > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        for frame in 0..<frameCount {
            let slot = (writeIndex + frame) % capacity
            for channel in 0..<channelCount {
                let source: Float
                if interleaved {
                    guard let base = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    source = base[frame * channelCount + channel]
                } else {
                    let index = min(channel, buffers.count - 1)
                    guard let base = buffers[index].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    source = base[frame]
                }
                planes[channel][slot] = source
            }
        }

        writeIndex = (writeIndex + frameCount) % capacity
        filled = min(filled + frameCount, capacity)

        if filled > maximumFill {
            let overflow = filled - maximumFill
            readIndex = (readIndex + overflow) % capacity
            filled = maximumFill
        }
    }

    func read(into bufferList: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        lock.lock()
        let deliverable = min(frameCount, filled)
        let startIndex = readIndex
        if deliverable > 0 {
            readIndex = (readIndex + deliverable) % capacity
            filled -= deliverable
        }
        let snapshot = planes
        lock.unlock()

        for (channel, buffer) in bufferList.enumerated() {
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let plane = snapshot[min(channel, snapshot.count - 1)]
            for frame in 0..<deliverable {
                destination[frame] = plane[(startIndex + frame) % capacity]
            }
            if deliverable < frameCount {
                for frame in deliverable..<frameCount { destination[frame] = 0 }
            }
        }
    }
}
