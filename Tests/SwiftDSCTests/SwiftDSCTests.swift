import XCTest
@testable import SwiftDSC
import Foundation
import RTLSDRWrapper
import SignalTools
import Accelerate


final class SwiftDSCTests: XCTestCase {
    
    static var testPath960k = Bundle.module.path(forResource: "dsc_test_low_power_960k", ofType: "wav")
    static var testPath240k = Bundle.module.path(forResource: "dsc_test_low_power_240k", ofType: "wav")
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
        let times240k = try getEnergyDetectionTimes(samples: samples240k, sampleRate: 240000, signalFrequencyOffset: 24000)
        let times960k = try getEnergyDetectionTimes(samples: samples960k, sampleRate: 960000, signalFrequencyOffset: 24000)
        
        
        // For first sample ('250k') -- Signal is from 0.71 to 1.08 s
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
            XCTAssertTrue(times960k[0].0 > 2.27 && times960k[0].0 < 2.33)
            XCTAssertTrue(times960k[0].1 > 3.1 && times960k[0].1 < 3.18)
        }
        else {
            XCTFail("Found no high energy times in first (960k) sample.")
        }
    }
    
    func testVHFDSCDemodulation() throws {
        guard var samples960k = SwiftDSCTests.testCall960k else { XCTFail("Failed to load test samples (960k)"); return }
        let testReceiver = try VHFDSCReceiver(inputSampleRate: 960000, internalSampleRate: 48000)
        var preprocessed = testReceiver.preprocessor.processSignal(&samples960k)
        testReceiver.processor.filterRawSignal(&preprocessed)
        let signal = Array(testReceiver.processor.frequencyOverTime(preprocessed)[122355..<148800]) // Start hardcoded based on python viz
        
        guard let (bits, _) = testReceiver.decoder.demodulateToBits(samples: signal) else { XCTFail("Failed to decode bits from signal."); return }
        let bitstring = bits.getBitstring()
        let bitstringFirst30 = bitstring[bitstring.startIndex..<bitstring.index(bitstring.startIndex, offsetBy: 30)]
        XCTAssert(bitstringFirst30 == "101010101010101010101011111001") // From known-good decoding instance in python prototype
    }
    
    func testVHFDSCDotPatternDiscovery() throws { // Note: this test is dependent on demodulation & energy detection both being functional.
        guard var samples960k = SwiftDSCTests.testCall960k else { XCTFail("Failed to load test samples (960k)"); return }
        let testReceiver = try VHFDSCReceiver(inputSampleRate: 960000, internalSampleRate: 48000)
        var preprocessed = testReceiver.preprocessor.processSignal(&samples960k)
        testReceiver.processor.filterRawSignal(&preprocessed)
        let times = try getEnergyDetectionTimes(samples: samples960k, sampleRate: 960000, signalFrequencyOffset: 0)
        let (startIndex, endIndex) = (timeToSampleIndex(times[0].0, sampleRate: 48000), timeToSampleIndex(times[0].1, sampleRate: 48000))
        let sliced = Array(preprocessed[startIndex..<endIndex])
        let signal = testReceiver.processor.frequencyOverTime(sliced)
        
        var dotPatternTime = TimeOperation(operationName: "Finding dot pattern in \(endIndex - startIndex) samples")
        guard let dotPatternIndex = testReceiver.synchronizer.findDotPatternStart(audio: signal) else { XCTFail("Failed to find dot pattern in signal."); return }
        print(dotPatternTime.stop())
    }
    
}




// Helpers

private func getEnergyDetectionTimes(samples: [DSPComplex], sampleRate: Int, signalFrequencyOffset: Int) throws -> [(Double, Double)] {
    var signalPrepTimer = TimeOperation(operationName: "Signal preparation")
    let receiver = try VHFDSCReceiver(inputSampleRate: sampleRate, internalSampleRate: 48000)
    var samplesCopy = samples
    let processedSignal = receiver.preprocessor.processSignal(&samplesCopy)
    print(signalPrepTimer.stop())
    
    var energyDetectionTimer = TimeOperation(operationName: "Energy detection")
    let times = receiver.getHighEnergyTimes(processedSignal)
    print(energyDetectionTimer.stop())
    print(times)
    return times
}


