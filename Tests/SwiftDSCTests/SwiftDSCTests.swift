import XCTest
@testable import SwiftDSC
import Foundation
import RTLSDRWrapper
import SignalTools
import Accelerate


final class SwiftDSCTests: XCTestCase {
    
    static var testPath960k = Bundle.module.path(forResource: "dsc_test_low_power_960k", ofType: "wav")
    static var testPath240k = Bundle.module.path(forResource: "dsc_test_low_power_240k", ofType: "wav")
    static var testPathAudio288k = Bundle.module.path(forResource: "dsc_call_audio_mono_288k", ofType: "wav")
    static var testCall960k: [DSPComplex]? = {
        do {
            var timeOpeningFile = TimeOperation(operationName: "Opening dsc_test_low_power_960k.wav")
            let samples = try readIQFromWAV16Bit(filePath: testPath960k!)
            print(timeOpeningFile.stop())
            var timeCorrectingFrequency = TimeOperation(operationName: "Correcting frequency dsc_test_low_power_960k.wav")
            var frequencyCorrected = [DSPComplex].init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: samples.count)
            shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &frequencyCorrected, frequency: 24000, sampleRate: 960000)
            print(timeCorrectingFrequency.stop())
            return frequencyCorrected
        }
        catch {
            return nil
        }
    }()
    static var testCall240k: [DSPComplex]? = {
        do {
            var timeOpeningFile = TimeOperation(operationName: "Opening dsc_test_low_power_240k.wav")
            let samples = try readIQFromWAV16Bit(filePath: testPath240k!)
            print(timeOpeningFile.stop())
            var timeCorrectingFrequency = TimeOperation(operationName: "Correcting frequency dsc_test_low_power_240k.wav")
            var frequencyCorrected = [DSPComplex].init(repeating: DSPComplex(real: 0.0, imag: 0.0), count: samples.count)
            shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &frequencyCorrected, frequency: 24000, sampleRate: 240000)
            print(timeCorrectingFrequency.stop())
            return frequencyCorrected
        }
        catch {
            return nil
        }
    }()
    static var testCallAudio288k: [Float]? = {
        do {
            var timeOpeningFile = TimeOperation(operationName: "Opening dsc_call_audio_288k.wav")
            let samples = try readAudioFromWAV16Bit(filePath: testPathAudio288k!)
            print(timeOpeningFile.stop())
            return samples
        }
        catch {
            return nil
        }
    }()
    
    
    
    // DSCSymbol tests
    func testReverseBits() {
        XCTAssertTrue(reverseBits(0b00000001) == 0b10000000)
    }
    
    func testDSCSymbolsandCode() {
        
        /// Count zeroes in a UInt16
        func countZeroes(_ code: UInt16) -> Int {
            return 7 - (code >> 3).nonzeroBitCount
        }
        
        /// Get the last 3 digits of UInt16 number
        /// Spec defines that this should be the value, in binary, of the number of zeroes in the code.
        func extractStatedZeroCount(_ code: UInt16) -> Int {
            return Int(code & 0b111)
        }
        
        // Hardcoded tests: Symbol --> Code
        // Values sourced from ITU-R M.493-16 Table A1-1
        XCTAssertTrue(DSC_SYMBOL_TO_CODE[0] == 0b0000000111)
        XCTAssertTrue(DSC_SYMBOL_TO_CODE[1] == 0b1000000110)
        XCTAssertTrue(DSC_SYMBOL_TO_CODE[43] == 0b1101010011)
        XCTAssertTrue(DSC_SYMBOL_TO_CODE[85] == 0b1010101011)
        XCTAssertTrue(DSC_SYMBOL_TO_CODE[127] == 0b1111111000)
        
        
        // Testing to ensure every code's ending 3 digits are equal to the number of zeroes, in binary.
        for num: UInt8 in 0..<128 {
            guard let code = DSC_SYMBOL_TO_CODE[num] else {
                XCTFail(String(format: "Missing code for symbol %d", num))
                return
            }
            // print("\(num): \(String(code, radix: 2))")
            XCTAssertEqual(countZeroes(code), extractStatedZeroCount(code))
        }
        
        // Hardcoded tests: Code --> Symbol
        // Values sourced from ITU-R M.493-16 Table A1-1
        XCTAssertTrue(DSC_CODE_TO_SYMBOL[0b0000000111] == 0)
        XCTAssertTrue(DSC_CODE_TO_SYMBOL[0b1000000110] == 1)
        XCTAssertTrue(DSC_CODE_TO_SYMBOL[0b0101010100] == 42)
        XCTAssertTrue(DSC_CODE_TO_SYMBOL[0b0000010110] == 32)
    }
    
    func testVHFDSCEnergyDetection() throws {
        guard let samples240k = SwiftDSCTests.testCall240k else { XCTFail("Failed to load test samples (240k)"); return }
        guard let samples960k = SwiftDSCTests.testCall960k else { XCTFail("Failed to load test samples (960k)"); return }
        let times240k = try getEnergyDetectionTimes(samples: samples240k, sampleRate: 240000, signalFrequencyOffset: 23500)
        let times960k = try getEnergyDetectionTimes(samples: samples960k, sampleRate: 960000, signalFrequencyOffset: 23500)
        
        
        // For first sample ('240k') -- Signal is from 0.71 to 1.08 s
        XCTAssertTrue(times240k.count == 1)
        if(times240k.count >= 1) {
            XCTAssertTrue(times240k[0].0 > 0.65 && times240k[0].0 < 0.71)
            XCTAssertTrue(times240k[0].1 > 1.08 && times240k[0].1 < 1.15)
        }
        else {
            XCTFail("Found no high energy times in first (240k) sample.")
        }
        
        // For second sample ('960k') -- Signal is from 2.33 to 3.1 s
        XCTAssertTrue(times960k.count == 1)
        if(times960k.count >= 1) {
            XCTAssertTrue(times960k[0].0 > 2.26 && times960k[0].0 < 2.33)
            XCTAssertTrue(times960k[0].1 > 3.1 && times960k[0].1 < 3.18)
        }
        else {
            XCTFail("Found no high energy times in first (960k) sample.")
        }
    }
    
    func testVHFDSCDemodulation() throws {
        guard var samples960k = SwiftDSCTests.testCall960k else { XCTFail("Failed to load test samples (960k)"); return }
        let testReceiver = try VHFDSCReceiver(inputSampleRate: 960000, internalSampleRate: 48000, debugConfig: DebugConfiguration(debugOutput: .extensive))
        var preprocessed = testReceiver.preprocessor.processSignal(&samples960k)
        testReceiver.processor.filterRawSignal(&preprocessed)
        let signal = Array(testReceiver.processor.frequencyOverTime(preprocessed)[122355..<148800]) // Start hardcoded based on python viz
        
        guard let (bits, _, _) = testReceiver.decoder.demodulateToBits(samples: signal) else { XCTFail("Failed to decode bits from signal."); return }
        let bitstring = bits.getBitstring()
        let bitstringFirst30 = bitstring[bitstring.startIndex..<bitstring.index(bitstring.startIndex, offsetBy: 30)]
        XCTAssert(bitstringFirst30 == "101010101010101010101011111001") // From known-good decoding instance in python prototype
    }
    
    func testVHFDSCDotPatternDiscovery() throws { // Note: this test is dependent on demodulation & energy detection both being functional.
        guard var samples960k = SwiftDSCTests.testCall960k else { XCTFail("Failed to load test samples (960k)"); return }
        let useSampleRate = 12000
        let samplesPerSymbol = useSampleRate / 1200
        let testReceiver = try VHFDSCReceiver(inputSampleRate: 960000, internalSampleRate: useSampleRate, debugConfig: DebugConfiguration(debugOutput: .extensive))
        var preprocessed = testReceiver.preprocessor.processSignal(&samples960k)
        testReceiver.processor.filterRawSignal(&preprocessed)
        let times = try getEnergyDetectionTimes(samples: samples960k, sampleRate: 960000, signalFrequencyOffset: 0)
        let (startIndex, endIndex) = (timeToSampleIndex(times[0].0, sampleRate: useSampleRate), timeToSampleIndex(times[0].1, sampleRate: useSampleRate))
        let sliced = Array(preprocessed[startIndex..<endIndex])
        let signal = testReceiver.processor.frequencyOverTime(sliced)
        
        // Dot pattern discovery / verification
        var dotPatternTime = TimeOperation(operationName: "Finding dot pattern in \(endIndex - startIndex) samples")
        guard let dotPatternIndex = testReceiver.synchronizer.findDotPatternStart(audio: signal) else { XCTFail("Failed to find dot pattern in signal."); return }
        print(dotPatternTime.stop())
        guard let bitsFromDotPatternIndex = testReceiver.decoder.demodulateToBits(samples: Array(signal[dotPatternIndex..<dotPatternIndex+(30 * samplesPerSymbol)])) else { XCTFail("Failed to demodulate"); return }
        let bitstringFromDotPatternIndex = bitsFromDotPatternIndex.0.getBitstring()
        guard let indexRangeOfStartSymbol = bitstringFromDotPatternIndex.range(of: "1011111001") else { // Looks for symbol '125' as it's the first DX symbol.
            XCTFail("Dot pattern starting index is not aligned properly."); return;
        }
        let numberOfSamplesToSkip = bitstringFromDotPatternIndex.distance(from: bitstringFromDotPatternIndex.startIndex, to: indexRangeOfStartSymbol.lowerBound) * samplesPerSymbol // Number of bits to skip in order to perfectly align with first DX symbol (bit-wise, not sample-wise.)
        var emptyContext = BitBuffer()
        guard let decodeFromStartingIndex = testReceiver.decoder.decodeToSymbols(samples: Array(signal[dotPatternIndex + numberOfSamplesToSkip..<signal.count]), context: &emptyContext) else { XCTFail("Failed to decode symbols from starting index."); return }
        let symbolsFromStartingIndex = decodeFromStartingIndex.0
        
        // First 16 symbols contain entire phasing sequence.
        guard symbolsFromStartingIndex.count > 16 else { XCTFail("Did not decode enough symbols to determine if alignment is valid."); return }
        let phasingSymbols = Array(symbolsFromStartingIndex[0..<16])
        let (dxPhasingSymbols, rxPhasingSymbols) = splitDXRX(symbols: phasingSymbols)
        XCTAssert(Array(dxPhasingSymbols[0..<6]) == DX_PHASING_SEQUENCE)
        XCTAssert(rxPhasingSymbols == RX_PHASING_SEQUENCE)
    }
    
    func testVHFDSCUnlockedStateHandling() throws {
        guard let samples960k = SwiftDSCTests.testCall960k else { XCTFail("Failed to load samples (960k)"); return }
        let useSampleRate = 12000
        let rawSamplesPerBit = 960000 / 1200
        
        // Splitting signal into noteworthy segments to simulate streaming scenario where whole signal isn't contained in one buffer input.
        let twentyFiveBitDuration = 25.0 / 1200.0 // Duration (s) of the first 30 bits given 1200 baud
        let dotPatternEndSample = timeToSampleIndex(2.55 + twentyFiveBitDuration, sampleRate: 960000)
        let dotPattern = Array(samples960k[0..<dotPatternEndSample]) // Containing 0th sample all the way up to dot pattern plus some padding.
        
        let firstPhasingCharacterEndSample = dotPatternEndSample + (rawSamplesPerBit * 10) // End of dot pattern (w/ padding) to end of first phasing char.
        let firstPhasingCharacter = Array(samples960k[dotPatternEndSample..<firstPhasingCharacterEndSample])
        
        let phasingSequenceEndSample = firstPhasingCharacterEndSample + (rawSamplesPerBit * 10 * 16) // 10 bits per symbol x 16 symbols in phasing seq
        let phasingSequence = Array(samples960k[firstPhasingCharacterEndSample..<phasingSequenceEndSample])

        // Trying to input **only** first <30 bits to make sure that state ends up in .unlocked(dotPatternIndex != -1, preciseStartFound: false)
        let testReceiver = try VHFDSCReceiver(inputSampleRate: 960000, internalSampleRate: useSampleRate, debugConfig: DebugConfiguration(debugOutput: .extensive))
        testReceiver.processSamples(dotPattern)
        XCTAssert(stateIsUnlockedWithDotPatternNoPreciseStart(state: testReceiver.state))
        
        // Now that dot pattern is found, inputting necessary bits to find precise start but **not** full phasing sequence.
        testReceiver.processSamples(firstPhasingCharacter)
        XCTAssert(stateIsUnlockedWithPreciseStart(state: testReceiver.state))
        
        // With dot pattern and precise start found, now looking for full phasing sequence.
        testReceiver.processSamples(phasingSequence)
        
        XCTAssert(testReceiver.state == .locked)
        let restOfSamples = Array(samples960k[phasingSequenceEndSample...])
        testReceiver.processSamples(restOfSamples)
    }
    
    func testMMSIFromSymbols() {
        let symbols: [DSCSymbol] = [DSCSymbol(symbol: 33)!, DSCSymbol(symbol: 85)!, DSCSymbol(symbol: 10)!, DSCSymbol(symbol: 24)!, DSCSymbol(symbol: 10)!] // MMSI: 338510241
        let testMMSI = MMSI(symbols: symbols)
        XCTAssert(testMMSI?.value == 338510241)
        XCTAssert(testMMSI?.description == "338510241")
        
        let cgSymbols: [DSCSymbol] = [DSCSymbol(symbol: 0)!, DSCSymbol(symbol: 36)!, DSCSymbol(symbol: 69)!, DSCSymbol(symbol: 99)!, DSCSymbol(symbol: 90)!] // MMSI: 003669999 (Coast Guard Test)
        let cgMMSI = MMSI(symbols: cgSymbols)
        XCTAssert(cgMMSI?.value == 3669999)
        XCTAssert(cgMMSI?.description == "003669999")
    }
    
    func testDirectAudioInput() throws {
        guard let audio288k = SwiftDSCTests.testCallAudio288k else { XCTFail("Failed to load testCallAudio288k"); return }
        let receiver = try VHFDSCReceiver(inputSampleRate: 288000, internalSampleRate: 12000, debugConfig: DebugConfiguration(debugOutput: .extensive))
        var callReceived = false
        receiver.setCallEmissionHandler { call in
            callReceived = true
            print(call.description)
        }
        receiver.processAudioInput(audio288k)
        XCTAssertTrue(callReceived)
    }
    
}




// Helpers

/// Gets output of EnergyDetector class for VHFDSCReceiver given a set of samples, sampleRate, and frequency offset of the signal.
/// Returns an array of start & end time pairs representing times where energy gate was passed.
private func getEnergyDetectionTimes(samples: [DSPComplex], sampleRate: Int, signalFrequencyOffset: Int) throws -> [(Double, Double)] {
    var signalPrepTimer = TimeOperation(operationName: "Signal preparation")
    let receiver = try VHFDSCReceiver(inputSampleRate: sampleRate, internalSampleRate: 48000, debugConfig: DebugConfiguration(debugOutput: .extensive))
    var samplesCopy = samples
    let processedSignal = receiver.preprocessor.processSignal(&samplesCopy)
    print(signalPrepTimer.stop())
    
    var energyDetectionTimer = TimeOperation(operationName: "Energy detection")
    let times = receiver.getHighEnergyTimes(processedSignal)
    print(energyDetectionTimer.stop())
    print(times)
    return times
}

/// Splits array of DSCSymbols into separate DX/RX branch arrays.
/// Assumes that first element is a DX element.
private func splitDXRX(symbols: [DSCSymbol]) -> ([DSCSymbol], [DSCSymbol]) {
    var dxSymbols: [DSCSymbol] = []
    var rxSymbols: [DSCSymbol] = []
    for i in stride(from: 0, to: symbols.count, by: 2) {
        if i + 1 < symbols.count {
            rxSymbols.append(symbols[i + 1])
        }
        dxSymbols.append(symbols[i])
    }
    return (dxSymbols, rxSymbols)
}

private func stateIsUnlockedWithDotPatternNoPreciseStart(state: DSCReceiverState) -> Bool {
    switch state {
    case .unlocked(let dotPatternIndex, let preciseStartFound):
        return !preciseStartFound && dotPatternIndex >= 0
    default:
        return false
    }
}

private func stateIsUnlockedWithPreciseStart(state: DSCReceiverState) -> Bool {
    switch state {
    case .unlocked(dotPatternIndex: _, preciseStartFound: true):
        return true
    default:
        return false
    }
}

