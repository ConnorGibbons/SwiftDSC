//
//  SignalProcessor.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/26/25.

import Foundation
import SignalTools

/// Handles filtering & FM demod / phase ('angle') extraction after preprocessing stage is done.
package class SignalProcessor {
    
    var sampleRate: Int
    var rawFilters: [FIRFilter] = []
    var impulseFilters: [FIRFilter] = []
    var angleFilters: [FIRFilter] = []
    var complexContext: ComplexSample? = nil // Used to provide context for the frequency over time function so the first output isn't dropped.
    
    var debugOutput: Bool
    
    init(sampleRate: Int, debugOutput: Bool = false) throws {
        self.sampleRate = sampleRate
        let defaultFinerFilter = try FIRFilter(type: .lowPass, cutoffFrequency: 5000, sampleRate: sampleRate, tapsLength: 31)
        let defaultImpulseFilter = try FIRFilter(type: .lowPass, cutoffFrequency: 2500, sampleRate: sampleRate, tapsLength: 13)
        self.rawFilters = [defaultFinerFilter]
        self.impulseFilters = [defaultImpulseFilter]
        self.angleFilters = []
        self.debugOutput = debugOutput
    }
    
    init(sampleRate: Int, rawFilters: [FIRFilter], impulseFilters: [FIRFilter], angleFilters: [FIRFilter], debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.rawFilters = rawFilters
        self.impulseFilters = impulseFilters
        self.angleFilters = angleFilters
        self.debugOutput = debugOutput
    }
    
    func filterRawSignal(_ signal: inout [ComplexSample]) {
        for filter in rawFilters {
            filter.filtfilt(&signal)
        }
    }
    
    func frequencyOverTime(_ signal: [ComplexSample]) -> [Float] {
        var input = signal
        if let context = complexContext {
            input.insert(context, at: 0)
        }
        let radianDiffs = demodulateFM(input)
        var frequencies = radToFrequency(radDiffs: radianDiffs, sampleRate: self.sampleRate)
        for filter in impulseFilters {
            filter.filteredSignal(&frequencies)
        }
        complexContext = signal.last ?? nil
        return frequencies
    }
    
    func angleOverTime(_ signal: [ComplexSample]) -> [Float] {
        var angles = [Float].init(repeating: 0, count: signal.count)
        calculateAngle(rawIQ: signal, result: &angles)
        unwrapAngle(&angles)
        for filter in angleFilters {
            filter.filtfilt(&angles)
        }
        return angles
    }
    
    func correctFrequencyError(signal: [ComplexSample], error: Float) -> [ComplexSample] {
        var correctedSignal: [ComplexSample] = .init(repeating: ComplexSample(real: 0.0, imag: 0.0), count: signal.count)
        shiftFrequencyToBaseband(rawIQ: signal, result: &correctedSignal, frequency: error, sampleRate: self.sampleRate)
        self.filterRawSignal(&correctedSignal)
        return correctedSignal
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print("Signal Processor: " + str)
        }
    }
    
}
