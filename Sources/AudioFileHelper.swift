import AVFoundation
import Foundation

enum AudioFileHelper {
    /// Writes PCM float samples to WAV file for warmup purposes
    static func writePCMToWAV(samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        
        let frameCapacity = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw NSError(domain: "AudioFileHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }
        
        buffer.frameLength = frameCapacity
        
        // Copy samples to buffer
        let channelData = buffer.floatChannelData![0]
        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }
        
        try audioFile.write(from: buffer)
    }
}