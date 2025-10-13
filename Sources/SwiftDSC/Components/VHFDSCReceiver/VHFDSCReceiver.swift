//
//  VHFDSCReceiver.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/4/25.
//

import Accelerate
import RTLSDRWrapper
import SignalTools

/// Enumerates the different states the receiver can be in.
/// waiting: Not currently receiving a transmission.
/// unlocked: Receiving dot pattern and phasing sequence, acquiring timing.
/// locked: Dot pattern + phasing complete, timing locked.
/// ending: Receiving ending sequence.
package enum DSCReveiverState: Equatable {
    case waiting
    case unlocked(dotPatternIndex: Int, preciseStartFound: Bool) // Index of dot pattern is stored (-1 if not found), and Bool based on whether precise start was found.
    case locked
    case ending
    
    var isUnlocked: Bool {
        if case .unlocked = self {
            return true
        }
        return false
    }
    
}

public enum DSCErrors: Error {
    case inputSampleRateTooLow
    case sampleRateMismatch
}


public class VHFDSCReceiver {
    // Constants
    let baud: Int = 1200
    let markFreq: Int = 1300
    let spaceFreq: Int = 2100
    let energyDetectionWindowSize = 0.025
    let energyDetectionResistance = 0.5
    let collapseTimesThreshold = 0.075
    let collapseTimesBuffer = 0.0
    let maxLockingRetries = 2
    
    // Parameters
    let inputSampleRate: Int
    let internalSampleRate: Int
    var emittedCallHandler: (DSCCall) -> Void = {
        print("VHF DSC Call Received: \($0.description)")
    }
    
    // State
    var state: DSCReveiverState
    var dx: [DSCSymbol] = []
    var dxConfirmed: [DSCSymbol] = [] // Storage for dx symbols that have passed errror checking / resolution.
    var rx: [DSCSymbol] = []
    var totalSymbolsReceived: Int = 0
    var bitCache: BitBuffer
    var audioCache: [Float]
    var retryCurrentTaskCounter: Int = 0
    
    // Debug
    var debugConfig: DebugConfiguration
    var debugBuffer: [Float] = []
    
    // Components
    package let energyDetector: EnergyDetector
    package let preprocessor: SignalPreprocessor
    package let processor: SignalProcessor
    package let decoder: VHFDSCPacketDecoder
    package let synchronizer: VHFDSCPacketSynchronizer
    package let validator: PacketValidator
    
    public init(inputSampleRate: Int, internalSampleRate: Int, debugConfig: DebugConfiguration) throws {
        guard inputSampleRate >= internalSampleRate else {
            throw DSCErrors.inputSampleRateTooLow
        }
        guard inputSampleRate % internalSampleRate == 0 else {
            print("Input sample rate must be a multiple of internal sample rate.")
            throw DSCErrors.sampleRateMismatch
        }
        guard internalSampleRate % 1200 == 0 else {
            print("Internal sample rate must be a multiple of 1200 (DSC Baud)")
            throw DSCErrors.sampleRateMismatch
        }
        
        // Parameters
        self.inputSampleRate = inputSampleRate
        self.internalSampleRate = internalSampleRate
        
        // State
        self.state = .waiting
        self.dx = []
        self.dxConfirmed = []
        self.rx = []
        self.totalSymbolsReceived = 0
        self.bitCache = BitBuffer()
        self.audioCache = []
        
        // Debug
        self.debugConfig = debugConfig
        
        // Components
        self.energyDetector = EnergyDetector(sampleRate: internalSampleRate, bufferDuration: 1, windowSize: 0.025, resistance: 0.5, debugOutput: true)
        self.preprocessor = SignalPreprocessor(inputSampleRate: inputSampleRate, outputSampleRate: internalSampleRate)
        self.processor = try SignalProcessor(sampleRate: internalSampleRate)
        self.decoder = VHFDSCPacketDecoder(sampleRate: internalSampleRate)
        self.synchronizer = VHFDSCPacketSynchronizer(sampleRate: internalSampleRate, decoder: decoder)
        self.validator = PacketValidator()
    }
    
    public func processSamples(_ samples: [DSPComplex]) {
        var samplesMutableCopy = samples
        let preprocessedSamples = self.preprocessor.processSignal(&samplesMutableCopy)
        switch state {
        case .waiting:
            guard let (startTime, endTime) = getHighEnergyTimes(preprocessedSamples).first else { return }
            let endSample = min(timeToSampleIndex(endTime, sampleRate: self.internalSampleRate), preprocessedSamples.count - 1) // Preventing out of bounds errors
            let startSample = max(timeToSampleIndex(startTime, sampleRate: self.internalSampleRate), 0)
//            Adjustment -- if high energy is detected, just use all of the samples. It's better than having some get left out.
//            let signalSamples = Array(preprocessedSamples[startSample...endSample])
            let signalSamples = preprocessedSamples
            let audio = self.processor.frequencyOverTime(signalSamples)
            self.state = .unlocked(dotPatternIndex: -1, preciseStartFound: false)
            processAudio(audio)
        default:
            let audio = self.processor.frequencyOverTime(preprocessedSamples)
            processAudio(audio)
        }
    }
    
    private func processAudio(_ audio: [Float]) {
        switch state {
        case .waiting:
            debugPrint("Hit a disallowed case -- processAudio called while state is 'waiting'.")
            return
        case .unlocked:
            unlockedAudioHandler(audio)
        case .locked:
            lockedAudioHandler(audio)
        case .ending:
            endingAudioHandler(audio)
        }
    }
    
    public func setCallEmissionHandler(_ handler: @escaping (DSCCall) -> Void) {
        self.emittedCallHandler = handler
    }
}
