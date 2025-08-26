//
//  SignalPreprocessor.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/25/25.
//

import Accelerate
import Foundation
import SignalTools

// Processes the signal prior to energy detection.
package class SignalPreprocessor {
    
    var inputSampleRate: Int
    var outputSampleRate: Int
    var filters: [Filter]
    let debugOutput: Bool
    var debugOutputPath: String = "/tmp/debugOutput.csv"
    
    init(inputSampleRate: Int, outputSampleRate: Int, debugOutput: Bool = false) {
        let defaultCoarseFilter = IIRFilter().addLowpassFilter(sampleRate: inputSampleRate, frequency: 10000, q: 0.707)
        self.inputSampleRate = inputSampleRate
        self.outputSampleRate = outputSampleRate
        self.filters = [defaultCoarseFilter]
        self.debugOutput = debugOutput
    }
    
    init(inputSampleRate: Int, outputSampleRate: Int, filters: [Filter], debugOutput: Bool = false) {
        self.inputSampleRate = inputSampleRate
        self.outputSampleRate = outputSampleRate
        self.filters = filters
        self.debugOutput = debugOutput
    }
    
    // Note that while this returns a new array, it does modify the original!
    func processSignal(_ signal: inout [DSPComplex]) -> [DSPComplex] {
        filterSignal(&signal)
        let resampled = resampleSignal(signal)
        if(debugOutput){
            // samplesToCSV(resampled, path: self.debugOutputPath)
        }
        return resampled
    }
    
    func filterSignal(_ signal: inout [DSPComplex]) {
        for filt in filters {
            filt.filteredSignal(&signal)
        }
    }
    
    func resampleSignal(_ signal: [DSPComplex]) -> [DSPComplex] {
        let antiAliasingFilter = try! FIRFilter(type: .lowPass, cutoffFrequency: Double(outputSampleRate / 2), sampleRate: inputSampleRate, tapsLength: 15)
        let resampled = downsampleComplex(iqData: signal, decimationFactor: inputSampleRate / outputSampleRate, filter: antiAliasingFilter.getTaps())
        return resampled
    }
    
    func addFilter(_ filter: Filter) {
        filters.append(filter)
    }
    
}
