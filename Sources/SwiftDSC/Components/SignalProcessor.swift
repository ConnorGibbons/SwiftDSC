//
//  SignalProcessor.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/26/25.
//
import Accelerate
import Foundation
import RTLSDRWrapper
import SignalTools

/// Handles filtering & FM demod / phase ('angle') extraction after preprocessing stage is done.
package class SignalProcessor {
    
    var sampleRate: Int
    var rawFilters: [FIRFilter] = []
    var impulseFilters: [FIRFilter] = []
    var angleFilters: [FIRFilter] = []
    
    var debugOutput: Bool
    
    init(sampleRate: Int, debugOutput: Bool = false) throws {
        self.sampleRate = sampleRate
        let defaultFinerFilter = try FIRFilter(type: .lowPass, cutoffFrequency: 5000, sampleRate: sampleRate, tapsLength: 31)
        let defaultImpulseFilter = try FIRFilter(type: .lowPass, cutoffFrequency: 2500, sampleRate: sampleRate, tapsLength: 15)
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
    
    func filterRawSignal(_ signal: inout [DSPComplex]) {
        for filter in rawFilters {
            filter.filtfilt(&signal)
        }
    }
    
    func frequencyOverTime(_ signal: [DSPComplex]) -> [Float] {
        let radianDiffs = demodulateFM(signal)
        var frequencies = radToFrequency(radDiffs: radianDiffs, sampleRate: self.sampleRate)
        for filter in impulseFilters {
            filter.filtfilt(&frequencies)
        }
        return frequencies
    }
    
    func angleOverTime(_ signal: [DSPComplex]) -> [Float] {
        var angles = [Float].init(repeating: 0, count: signal.count)
        calculateAngle(rawIQ: signal, result: &angles)
        unwrapAngle(&angles)
        for filter in angleFilters {
            filter.filtfilt(&angles)
        }
        return angles
    }
    
    func correctFrequencyError(signal: [DSPComplex], error: Float) -> [DSPComplex] {
        var correctedSignal: [DSPComplex] = .init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: signal.count)
        shiftFrequencyToBaseband(rawIQ: signal, result: &correctedSignal, frequency: error, sampleRate: self.sampleRate)
        self.filterRawSignal(&correctedSignal)
        return correctedSignal
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
        }
    }
    
}
