import Foundation
import AVFoundation

/// Real-time procedural synth audio engine + dynamic B1/B2/B3 stratum reverb (`audio_bus_controller.gd` equivalent)
public final class AudioSynthEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let reverbNode = AVAudioUnitReverb()
    private let format: AVAudioFormat
    private var isRunning = false
    private var currentStratum: Stratum = .b1Atrium

    public var isMuted: Bool = false

    public init() {
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 2)!
        setupAudioGraph()
    }

    private func setupAudioGraph() {
        engine.attach(playerNode)
        engine.attach(reverbNode)

        reverbNode.loadFactoryPreset(.largeHall2)
        reverbNode.wetDryMix = currentStratum.reverbWetMix

        engine.connect(playerNode, to: reverbNode, format: format)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55

        do {
            try engine.start()
            playerNode.play()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    /// Dynamically adjusts reverb wet/dry mix based on B1/B2/B3 depth (README Section 6)
    public func updateStratumReverb(_ stratum: Stratum) {
        guard stratum != currentStratum else { return }
        currentStratum = stratum
        reverbNode.wetDryMix = stratum.reverbWetMix
    }

    public func play(_ event: SoundEventKind) {
        guard isRunning && !isMuted else { return }

        switch event {
        case .footstep:
            scheduleSynth(duration: 0.055, startFreq: 135, endFreq: 52, noiseMix: 0.35, gain: 0.16)
        case .jump:
            scheduleSynth(duration: 0.09, startFreq: 180, endFreq: 340, noiseMix: 0.08, gain: 0.20)
        case .dodge(let wall):
            scheduleSynth(
                duration: 0.14,
                startFreq: wall ? 320 : 210,
                endFreq: wall ? 620 : 410,
                noiseMix: 0.28,
                gain: 0.28
            )
        case .jumpPad:
            scheduleSynth(duration: 0.28, startFreq: 220, endFreq: 880, noiseMix: 0.05, gain: 0.34)
        case .teleport:
            scheduleSynth(duration: 0.32, startFreq: 660, endFreq: 190, noiseMix: 0.15, gain: 0.32)
        case .weaponFire(let slot, let alt):
            switch slot {
            case .kineticGauntlet:
                scheduleSynth(duration: 0.15, startFreq: alt ? 280 : 160, endFreq: 65, noiseMix: 0.30, gain: 0.32)
            case .prismRifle:
                scheduleSynth(duration: alt ? 0.22 : 0.16, startFreq: alt ? 520 : 980, endFreq: alt ? 180 : 240, noiseMix: 0.10, gain: 0.30)
            case .shardCannon:
                scheduleSynth(duration: 0.18, startFreq: 240, endFreq: 75, noiseMix: 0.55, gain: 0.34)
            case .vectorLauncher:
                scheduleSynth(duration: 0.24, startFreq: 150, endFreq: 48, noiseMix: 0.45, gain: 0.36)
            case .subRail:
                scheduleSynth(duration: 0.30, startFreq: 1320, endFreq: 110, noiseMix: 0.18, gain: 0.35)
            }
        case .shockCombo:
            scheduleSynth(duration: 0.48, startFreq: 420, endFreq: 36, noiseMix: 0.35, gain: 0.48)
        case .explosion:
            scheduleSynth(duration: 0.30, startFreq: 140, endFreq: 38, noiseMix: 0.50, gain: 0.36)
        case .breachShatter:
            scheduleSynth(duration: 0.34, startFreq: 1600, endFreq: 280, noiseMix: 0.65, gain: 0.38)
        case .pickup:
            scheduleSynth(duration: 0.18, startFreq: 523.25, endFreq: 1046.5, noiseMix: 0.02, gain: 0.26)
        case .hitMarker(let kill):
            scheduleSynth(duration: kill ? 0.16 : 0.06, startFreq: kill ? 1480 : 1120, endFreq: kill ? 1960 : 880, noiseMix: 0.0, gain: 0.28)
        }
    }

    private func scheduleSynth(duration: Float, startFreq: Float, endFreq: Float, noiseMix: Float, gain: Float) {
        let frameCount = AVAudioFrameCount(max(64, Int(duration * Float(format.sampleRate))))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        guard let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else { return }

        var phase: Float = 0.0
        let sr = Float(format.sampleRate)
        var rngState: UInt32 = 0x12345678

        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(frameCount)
            let env = pow(1.0 - t, 1.65) * min(1.0, t * 25.0)
            let freq = startFreq + (endFreq - startFreq) * t
            phase += (2.0 * .pi * freq) / sr

            // Fast LCG white noise
            rngState = rngState &* 1664525 &+ 1013904223
            let noise = (Float(rngState & 0xFFFF) / 32768.0) - 1.0

            let tone = sin(phase) + 0.3 * sin(phase * 2.0)
            let sample = ((1.0 - noiseMix) * tone + noiseMix * noise) * env * gain
            left[i] = sample
            right[i] = sample
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}
