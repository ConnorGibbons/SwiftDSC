//
//  offlineTesting.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/29/25.
//
import Foundation
import SignalTools
import RTLSDRWrapper
import Accelerate

func offlineTesting(state: RuntimeState) throws {
    guard let centerFrequency = state.offlineCenterFrequency, let sampleRate = state.offlineSampleRate, let samples = state.offlineSamples else {
        print("Missing data required for offline testing.")
        exit(1)
    }
    
    var timer = TimeOperation(operationName: "Preparing data")
    var centeredDataBuffer: [DSPComplex] = .init(repeating: DSPComplex(real: 0, imag: 0), count: samples.count) // Data frequency shifted to have VHF Channel 70 at 0 Hz
    shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &centeredDataBuffer, frequency: Float(VHF_DSC_CENTER_FREQUENCY - centerFrequency), sampleRate: sampleRate)
    print(timer.stop())
    
    let receiver = try VHFDSCReceiver(inputSampleRate: sampleRate, internalSampleRate: 12000)
    var calls: [DSCCall] = []
    receiver.setCallEmissionHandler{ newCall in
        calls.append(newCall)
    }
    let splitSamples = splitArray(centeredDataBuffer, sectionSize: MIN_BUFFER_LEN)
    print(splitSamples[0].count)
    
    var processingTimer = TimeOperation(operationName: "Processing data")
    for samples in splitSamples {
        receiver.processSamples(samples)
    }
    print(processingTimer.stop())
    
    
    for call in calls {
        handleCall(call, state: state)
    }
    
}
