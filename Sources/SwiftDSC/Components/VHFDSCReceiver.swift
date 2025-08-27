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
package enum DSCReveiverState {
    case waiting(dotPatternComplete: Bool, phasingComplete: Bool)
    case unlocked
    case locked
    case ending
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
    
    // Parameters
    let inputSampleRate: Int
    let internalSampleRate: Int
    
    // State
    var state: DSCReveiverState
    var dx: [DSCSymbol] = []
    var rx: [DSCSymbol] = []
    
    // Components
    package let energyDetector: EnergyDetector
    package let preprocessor: SignalPreprocessor
    package let processor: SignalProcessor
    package let decoder: VHFDSCPacketDecoder
    package let synchronizer: VHFDSCPacketSynchronizer
    
    public init(inputSampleRate: Int, internalSampleRate: Int) throws {
        guard inputSampleRate >= internalSampleRate else {
            throw DSCErrors.inputSampleRateTooLow
        }
        guard inputSampleRate % internalSampleRate == 0 else {
            print("Input sample rate must be a multiple of internal sample rate.")
            throw DSCErrors.sampleRateMismatch
        }
        guard internalSampleRate % 1200 == 0 else {
            print("Internal sample rate must be a multiple of 9600 (AIS Baud)")
            throw DSCErrors.sampleRateMismatch
        }
        
        // Parameters
        self.inputSampleRate = inputSampleRate
        self.internalSampleRate = internalSampleRate
        
        // State
        self.state = .waiting(dotPatternComplete: false, phasingComplete: false)
        self.dx = []
        self.rx = []
        
        // Components
        self.energyDetector = EnergyDetector(sampleRate: internalSampleRate, bufferDuration: 1, windowSize: 0.025, resistance: 0.5)
        self.preprocessor = SignalPreprocessor(inputSampleRate: inputSampleRate, outputSampleRate: internalSampleRate)
        self.processor = try SignalProcessor(sampleRate: internalSampleRate)
        self.decoder = VHFDSCPacketDecoder(sampleRate: internalSampleRate)
        self.synchronizer = VHFDSCPacketSynchronizer(sampleRate: internalSampleRate, decoder: decoder)
    }
    
    package func getHighEnergyTimes(_ signal: [DSPComplex]) -> [(Double, Double)] {
        var samplesToProcess: [[DSPComplex]] = []
        if(signal.count > energyDetector.bufferSize) {
            samplesToProcess = splitArray(signal, sectionSize: energyDetector.bufferSize)
        }
        else {
            samplesToProcess.append(signal)
        }
        
        var highEnergyIndices: [Int] = []
        var currentChunkNum = 0
        while(currentChunkNum < samplesToProcess.count) {
            var newHighEnergyIndicies = self.energyDetector.addSamples(samplesToProcess[currentChunkNum])
            addBufferOffsetToIndexArray(&newHighEnergyIndicies, currentChunkNum)
            highEnergyIndices.append(contentsOf: newHighEnergyIndicies)
            currentChunkNum += 1
        }
        guard highEnergyIndices.count > 1 else {
            // debugPrint("Exited early due to not finding enough high energy indicies")
            print("Exited early due to not finding enough high energy indicies")
            return []
        }
        
        let highEnergyTimes = highEnergyIndices.map { sampleIndexToTime($0, sampleRate: self.internalSampleRate) }
        return collapseTimeArray(highEnergyTimes, threshold: self.collapseTimesThreshold, addBuffer: self.collapseTimesBuffer)
    }
    
    package func addBufferOffsetToIndexArray(_ indexArray: inout [Int], _ bufferOffset: Int) {
        var index = 0
        let bufferIndexOffset = bufferOffset * self.energyDetector.bufferSize
        while index < indexArray.count {
            indexArray[index] += bufferIndexOffset
            index += 1
        }
    }
    
}

