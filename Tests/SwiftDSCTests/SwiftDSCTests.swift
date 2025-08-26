import XCTest
@testable import SwiftDSC
import Foundation
import RTLSDRWrapper
import SignalTools
import Accelerate


final class SwiftDSCTests: XCTestCase {
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
        guard let testPath240k = Bundle.module.path(forResource: "dsc_test_low_power_240k", ofType: "wav") else {
            XCTFail("Could not find test file")
            return
        }
        guard let testPath960k = Bundle.module.path(forResource: "dsc_test_low_power_960k", ofType: "wav") else {
            XCTFail("Could not find test file")
            return
        }
        
        let samples240k = try readIQFromWAV16Bit(filePath: testPath240k)
        let samples960k = try readIQFromWAV16Bit(filePath: testPath960k)
        
        let times240k = try getEnergyDetectionTimes(samples: samples240k, sampleRate: 240000, signalFrequencyOffset: 24000)
        let times960k = try getEnergyDetectionTimes(samples: samples960k, sampleRate: 960000, signalFrequencyOffset: 24000)
        
        
        // For first sample ('250k')
        XCTAssertTrue(times240k.count == 1)
        if(times240k.count >= 1) {
            XCTAssertTrue(times240k[0].0 > 0.65 && times240k[0].0 < 0.71) // W/ padding at the start & ensuring none of the signal is missed
            XCTAssertTrue(times240k[0].1 > 1.08 && times240k[0].1 < 1.15)
        }
        else {
            XCTFail("Found no high energy times in first (240k) sample.")
        }
        
        // For second sample ('960k')
        XCTAssertTrue(times960k.count == 1)
        if(times960k.count >= 1) {
            XCTAssertTrue(times960k[0].0 > 2.27 && times960k[0].0 < 2.33) // W/ padding at the start & ensuring none of the signal is missed
            XCTAssertTrue(times960k[0].1 > 3.1 && times960k[0].1 < 3.18)
        }
        else {
            XCTFail("Found no high energy times in first (960k) sample.")
        }
    }
    
}




// Helpers

private func getEnergyDetectionTimes(samples: [DSPComplex], sampleRate: Int, signalFrequencyOffset: Int) throws -> [(Double, Double)] {
    var signalPrepTimer = TimeOperation(operationName: "Signal preparation")
    var samplesShifted: [DSPComplex] = .init(repeating: .init(real: 0, imag: 0), count: samples.count)
    let receiver = try VHFDSCReceiver(inputSampleRate: sampleRate, internalSampleRate: 48000)
    shiftFrequencyToBasebandHighPrecision(rawIQ: samples, result: &samplesShifted, frequency: Float(signalFrequencyOffset), sampleRate: sampleRate)
    let processedSignal = receiver.preprocessor.processSignal(&samplesShifted)
    print(signalPrepTimer.stop())
    
    var energyDetectionTimer = TimeOperation(operationName: "Energy detection")
    let times = receiver.getHighEnergyTimes(processedSignal)
    print(energyDetectionTimer.stop())
    print(times)
    return times
}


