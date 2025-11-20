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
    
    func testDSCFrequencyStruct() {
        // 90 0 6 126 126 126
        // Expected Result:
        // RX: VHF Channel 6 (HM = 9; H=0; T=0; U=6)
        // TX: None
        let freqSymbols0: [DSCSymbol] = [.init(symbol: 90)!,.init(symbol: 0)!,.init(symbol: 6)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!]
        let frequency0 = DSCFrequency(symbols: freqSymbols0)
        XCTAssert(frequency0 != nil)
        XCTAssert(frequency0?.vhfChannelNumber != nil && frequency0?.vhfChannelNumber!.0 == 6 && frequency0?.vhfChannelNumber!.1 == nil)
        XCTAssert(frequency0?.txFrequency == nil && frequency0?.rxFrequency == nil && frequency0?.mfHfChannelNumber == nil)
        
        // 90 0 40 126 126 126
        // Expected Result:
        // RX: VHF Channel 40 (HM = 9; H = 0; T = 4; U = 0)
        // TX: None
        let freqSymbols1: [DSCSymbol] = [.init(symbol: 90)!,.init(symbol: 0)!,.init(symbol: 40)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!]
        let frequency1 = DSCFrequency(symbols: freqSymbols1)
        XCTAssert(frequency1 != nil)
        XCTAssert(frequency1?.vhfChannelNumber != nil && frequency1?.vhfChannelNumber!.0 == 40 && frequency1?.vhfChannelNumber!.1 == nil)
        XCTAssert(frequency1?.txFrequency == nil && frequency1?.rxFrequency == nil && frequency1?.mfHfChannelNumber == nil)
        
        // 90 2 13 126 126 126
        // Expected Result:
        // RX: VHF Channel 213 (HM = 9; H = 2; T = 1; U = 3)
        // Anything above channel 88 is not a real VHF channel -- I don't know why the spec allows for this, but it is a valid input.
        // TX: None
        let freqSymbols2: [DSCSymbol] = [.init(symbol: 90)!,.init(symbol: 2)!,.init(symbol: 13)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!]
        let frequency2 = DSCFrequency(symbols: freqSymbols2)
        XCTAssert(frequency2 != nil)
        XCTAssert(frequency2?.vhfChannelNumber != nil && frequency2?.vhfChannelNumber!.0 == 213 && frequency2?.vhfChannelNumber!.1 == nil)
        XCTAssert(frequency2?.txFrequency == nil && frequency2?.rxFrequency == nil && frequency2?.mfHfChannelNumber == nil)
        
        // 90 0 23 90 0 23
        // Expected Result:
        // RX: VHF Channel 23 (HM = 9; H = 0; T = 2; U = 3)
        // TX: VHF Channel 23 (HM = 9; H = 0; T = 2; U = 3)
        let freqSymbols3: [DSCSymbol] = [.init(symbol: 90)!,.init(symbol: 0)!,.init(symbol: 23)!,.init(symbol: 90)!,.init(symbol: 0)!,.init(symbol: 23)!]
        let frequency3 = DSCFrequency(symbols: freqSymbols3)
        XCTAssert(frequency3 != nil)
        XCTAssert(frequency3?.vhfChannelNumber != nil && frequency3?.vhfChannelNumber!.0 == 23 && frequency3?.vhfChannelNumber!.1 == 23)
        XCTAssert(frequency2?.txFrequency == nil && frequency2?.rxFrequency == nil && frequency2?.mfHfChannelNumber == nil)
        
        // 41 11 11 11 126 126 126 126
        // Expected Result:
        // RX: 11111110 Hz (11,111.11 KHz) (TM = 1; M = 1; H = 1; T = 1; U = 1; T1 = 1; U1 = 1)
        // (Place value * Unit * Value)
        // (10000 * 1000 Hz * 1) + (1000 * 1000 Hz * 1) + (100 * 1000 * 1) + (10 * 1000 * 1) + (1 * 1000 * 1) + (10 * 10 * 1) + (1 * 10 * 1)
        // TX: None
        let freqSymbols4: [DSCSymbol] = [.init(symbol: 41)!,.init(symbol: 11)!,.init(symbol: 11)!,.init(symbol: 11)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!]
        let frequency4 = DSCFrequency(symbols: freqSymbols4)
        XCTAssert(frequency4 != nil)
        XCTAssert(frequency4?.rxFrequency == 11111110)
        XCTAssert(frequency4?.mfHfChannelNumber == nil && frequency4?.vhfChannelNumber == nil && frequency4?.txFrequency == nil)
        
        // 126 126 126 126 41 11 11 11
        // Expected Result:
        // RX: None
        // TX: 11111110 Hz (11,111.11 KHz) (TM = 1; M = 1; H = 1; T = 1; U = 1; T1 = 1; U1 = 1)
        let freqSymbols5: [DSCSymbol] = [.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 126)!,.init(symbol: 41)!,.init(symbol: 11)!,.init(symbol: 11)!,.init(symbol: 11)!]
        let frequency5 = DSCFrequency(symbols: freqSymbols5)
        XCTAssert(frequency5 != nil)
        XCTAssert(frequency5?.txFrequency == 11111110)
        XCTAssert(frequency5?.mfHfChannelNumber == nil && frequency5?.vhfChannelNumber == nil && frequency5?.rxFrequency == nil)
        
        // 30 12 1 126 126 126
        // Expected Result:
        // RX: MF/HF Channel 1201
        // TX: None
        let freqSymbols6: [DSCSymbol] = [.init(symbol: 30)!,.init(symbol: 12)!,.init(symbol: 1)!,.init(symbol:126)!,.init(symbol:126)!,.init(symbol:126)!]
        let frequency6 = DSCFrequency(symbols: freqSymbols6)
        XCTAssert(frequency6 != nil)
        XCTAssert(frequency6?.mfHfChannelNumber != nil && frequency6?.mfHfChannelNumber!.0 == 1201 && frequency6?.mfHfChannelNumber!.1 == nil)
        XCTAssert(frequency6?.rxFrequency == nil && frequency6?.txFrequency == nil && frequency6?.vhfChannelNumber == nil)
    }
    
    /// Tests whether the "getDSCCall" function successfully returns the correct call type for various inputs.
    func testDSCCallDispatch() {
        // Some IDs to use: 0,36,69,99,90 (003669999) -- 33,85,10,24,10 (338510241) -- 0,36,69,92,80 (003669928)
        // Pos1: 99,99,99,99,99 --> Signifies a missing position
        // UTC: 23,0 (23:00)
        
        let distressAlertSymbols = [112,112,0,36,69,99,90,110,99,99,99,99,99,23,0,100,127].map { DSCSymbol(symbol: $0)! }
        let distressCall = getDSCCall(callSymbols: distressAlertSymbols)
        XCTAssert(distressCall as? DistressAlert != nil)
    
        let distressAckSymbols = [116,116,112,0,36,69,99,90,110,33,85,10,24,10,110,99,99,99,99,99,23,0,100,127].map { DSCSymbol(symbol: $0)! }
        let distressAck = getDSCCall(callSymbols: distressAckSymbols)
        XCTAssert(distressAck as? DistressAcknowledgement != nil)
        
        let distressAlertRelaySymbols = [120,120,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,117].map { DSCSymbol(symbol: $0)! }
        let distressAlertRelay = getDSCCall(callSymbols: distressAlertRelaySymbols)
        XCTAssert(distressAlertRelay as? DistressAlertRelay != nil)
        
        // 'group' call -- format '114', EOS '127', nature of distress fixed '110'
        let distressAlertRelayGroupSymbols = [114,114,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,126,127].map { DSCSymbol(symbol: $0)! }
        let distressAlertRelayGroup = getDSCCall(callSymbols: distressAlertRelayGroupSymbols)
        XCTAssert(distressAlertRelayGroup as? DistressAlertRelay != nil)
        
        // 'All ships' call -- format '116', subsequent communications '100', EOS '127'.
        let distressAlertRelayAllShipsSymbols = [116,116,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,127].map { DSCSymbol(symbol: $0)! }
        let distressAlertRelayAllShips = getDSCCall(callSymbols: distressAlertRelayAllShipsSymbols)
        XCTAssert(distressAlertRelayAllShips as? DistressAlertRelay != nil)
        
        let distressAlertRelayAcknowledgementSymbols = [120,120,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,122].map { DSCSymbol(symbol: $0)! }
        let distressAlertRelayAcknowledgement = getDSCCall(callSymbols: distressAlertRelayAcknowledgementSymbols)
        XCTAssert(distressAlertRelayAcknowledgement as? DistressAlertRelayAcknowledgement != nil)
        
        let distressAlertRelayGroupAcknowledgementSymbols = [114,114,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,126,122].map { DSCSymbol(symbol: $0)! }
        let distressAlertRelayGroupAcknowledgement = getDSCCall(callSymbols: distressAlertRelayGroupAcknowledgementSymbols)
        XCTAssert(distressAlertRelayGroupAcknowledgement as? DistressAlertRelayAcknowledgement != nil)
        
        let distressAlertRelayAllShipsAcknowledgementSymbols = [116,116,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,122].map { DSCSymbol(symbol: $0)! }
        let distressAlertRelayAllShipsAcknowledgement = getDSCCall(callSymbols: distressAlertRelayAllShipsAcknowledgementSymbols)
        XCTAssert(distressAlertRelayAllShipsAcknowledgement as? DistressAlertRelayAcknowledgement != nil)
        
        // 'indvidual select' call
        let urgencyAndSafetyIndividualCallSymbols = [120,120,0,36,69,99,90,108,33,85,10,24,10,118,126,126,126,126,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        let urgencyAndSafetyIndividualCall = getDSCCall(callSymbols: urgencyAndSafetyIndividualCallSymbols)
        XCTAssert(urgencyAndSafetyIndividualCall as? UrgencyAndSafetyCall != nil)
        
        // 'All ships' call, and swapped '108' (safety) to '110' (urgency)
        let urgencyAndSafetyAllShipsCallSymbols = [116,116,110,33,85,10,24,10,118,126,126,126,126,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        let urgencyAndSafetyAllShipsCall = getDSCCall(callSymbols: urgencyAndSafetyAllShipsCallSymbols)
        XCTAssert(urgencyAndSafetyAllShipsCall as? UrgencyAndSafetyCall != nil)
        
        let routineIndividualCallSymbols = [120,120,24,73,65,0,0,100,24,73,65,0,0,100,126,90,0,6,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        let routineIndividualCall = getDSCCall(callSymbols: routineIndividualCallSymbols)
        XCTAssert(routineIndividualCall as? RoutineCall != nil)
        
        let routineGroupCallSymbols = [114,114,24,73,65,0,0,100,24,73,65,0,0,100,126,90,0,6,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        let routineGroupCall = getDSCCall(callSymbols: routineGroupCallSymbols)
        XCTAssert(routineGroupCall as? RoutineCall != nil)
    }
    
    func testDSCDistressAlert() {
        // Self ID: 003669999; Coordinates: Missing; Time: 23:00; Ack: Required
        let distressAlertSymbols = [112,112,0,36,69,99,90,110,99,99,99,99,99,23,0,100,127].map { DSCSymbol(symbol: $0)! }
        guard let distressCall = getDSCCall(callSymbols: distressAlertSymbols) as? DistressAlert else {
            XCTFail("distressCall did not get parsed to a DistressAlert type.")
            return
        }
        XCTAssert(distressCall.selfID.description == "003669999")
        XCTAssert(distressCall.distressCoordinates.quadrant == .missing)
        XCTAssert(distressCall.timeUTC.description == "23:00")
        XCTAssert(distressCall.natureOfDistress == .manOverboard)
        XCTAssert(distressCall.EOS == .other)
    }
    
    func testDSCDistressAlertAcknowledgement() {
        let distressAlertAcknowledgementSymbols = [116,116,112,0,36,69,99,90,110,33,85,10,24,10,110,99,99,99,99,99,23,0,100,127].map { DSCSymbol(symbol: $0)! }
        guard let distressAcknowledgement = getDSCCall(callSymbols: distressAlertAcknowledgementSymbols) as? DistressAcknowledgement else {
            XCTFail("distressAcknowledgement did not get parsed to a DistressAcknowledgemnet type.")
            return
        }
        XCTAssert(distressAcknowledgement.selfID.description == "003669999")
        XCTAssert(distressAcknowledgement.distressID.description == "338510241")
        XCTAssert(distressAcknowledgement.natureOfDistress == .manOverboard)
        XCTAssert(distressAcknowledgement.distressCoordinates.quadrant == .missing)
        XCTAssert(distressAcknowledgement.subsequentCommunications == DSCSymbol(symbol: 100)!)
    }
    
    func testDSCDistressAlertRelay() {
        let distressAlertRelaySymbols = [120,120,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,117].map { DSCSymbol(symbol: $0)! }
        guard let distressAlertRelay = getDSCCall(callSymbols: distressAlertRelaySymbols) as? DistressAlertRelay else {
            XCTFail("distressAlertRelay did not get parsed to a DistressAlertRelay type.")
            return
        }
        XCTAssert(distressAlertRelay.category == .distress)
        XCTAssert(distressAlertRelay.formatSpecifier == .individualStationSelective)
        XCTAssert(distressAlertRelay.address?.description == "003669999")
        XCTAssert(distressAlertRelay.selfID.description == "003669928")
        XCTAssert(distressAlertRelay.distressID.description == "338510241")
        XCTAssert(distressAlertRelay.natureOfDistress == .manOverboard)
        XCTAssert(distressAlertRelay.distressCoordinates.quadrant == .missing)
        XCTAssert(distressAlertRelay.subsequentCommunications == DSCSymbol(symbol: 100)!)
        XCTAssert(distressAlertRelay.EOS == .acknowledgementRequired)
        
        let distressAlertRelayGroupSymbols = [114,114,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,126,127].map { DSCSymbol(symbol: $0)! }
        guard let distressAlertRelayGroup = getDSCCall(callSymbols: distressAlertRelayGroupSymbols) as? DistressAlertRelay else {
            XCTFail("distressAlertRelayGroup did not get pased to a DistressAlertRelay type.")
            return
        }
        XCTAssert(distressAlertRelayGroup.category == .distress)
        XCTAssert(distressAlertRelayGroup.formatSpecifier == .commonInterestSelective)
        XCTAssert(distressAlertRelayGroup.address?.description == "003669999")
        XCTAssert(distressAlertRelayGroup.selfID.description == "003669928")
        XCTAssert(distressAlertRelayGroup.distressID.description == "338510241")
        XCTAssert(distressAlertRelayGroup.natureOfDistress == .manOverboard)
        XCTAssert(distressAlertRelayGroup.distressCoordinates.quadrant == .missing)
        XCTAssert(distressAlertRelayGroup.subsequentCommunications == DSCSymbol(symbol: 126)!)
        XCTAssert(distressAlertRelayGroup.EOS == .other)
        
        let distressAlertRelayAllShipsSymbols = [116,116,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,127].map { DSCSymbol(symbol: $0)! }
        guard let distressAlertRelayAllShips = getDSCCall(callSymbols: distressAlertRelayAllShipsSymbols) as? DistressAlertRelay else {
            XCTFail("distressAlertRelayAllShips did not get parsed to a DistressAlertRelay type.")
            return
        }
        XCTAssert(distressAlertRelayAllShips.category == .distress)
        XCTAssert(distressAlertRelayAllShips.formatSpecifier == .allShips)
        XCTAssert(distressAlertRelayAllShips.address == nil)
        XCTAssert(distressAlertRelayAllShips.selfID.description == "003669928")
        XCTAssert(distressAlertRelayAllShips.distressID.description == "338510241")
        XCTAssert(distressAlertRelayAllShips.natureOfDistress == .manOverboard)
        XCTAssert(distressAlertRelayAllShips.distressCoordinates.quadrant == .missing)
        XCTAssert(distressAlertRelayAllShips.subsequentCommunications == DSCSymbol(symbol: 100)!)
        XCTAssert(distressAlertRelayAllShips.EOS == .other)
    }
    
    func testDSCDistressAlertRelayAcnkowledgement() {
        let distressAlertRelayAcknowledgementSymbols = [120,120,0,36,69,99,90,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,122].map { DSCSymbol(symbol: $0)! }
        guard let distressAlertRelayAcknowledgement = getDSCCall(callSymbols: distressAlertRelayAcknowledgementSymbols) as? DistressAlertRelayAcknowledgement else {
            XCTFail("distresAlertRelayAcknowledgement did not get parsed to a DistressAlertRelayAcknowledgement type.")
            return
        }
        XCTAssert(distressAlertRelayAcknowledgement.address?.description == "003669999")
        XCTAssert(distressAlertRelayAcknowledgement.selfID.description == "003669928")
        XCTAssert(distressAlertRelayAcknowledgement.distressID.description == "338510241")
        XCTAssert(distressAlertRelayAcknowledgement.natureOfDistress == .manOverboard)
        XCTAssert(distressAlertRelayAcknowledgement.distressCoordinates.quadrant == .missing)
        XCTAssert(distressAlertRelayAcknowledgement.time.description == "23:00")
        XCTAssert(distressAlertRelayAcknowledgement.subsequentCommunications == DSCSymbol(symbol: 100)!)
        XCTAssert(distressAlertRelayAcknowledgement.EOS == .providingAcknowledgement)
        
        let distressAlertRelayAllShipsAcknowledgementSymbols = [116,116,112,0,36,69,92,80,112,33,85,10,24,10,110,99,99,99,99,99,23,0,100,122].map { DSCSymbol(symbol: $0)! }
        guard let distressAlertRelayAllShipsAcknowledgement = getDSCCall(callSymbols: distressAlertRelayAllShipsAcknowledgementSymbols) as? DistressAlertRelayAcknowledgement else {
            print("distressAlertRelayAllShipsAcknowledgement did not get parsed to a DistressAlertRelayAcknowledgement type.")
            return
        }
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.address == nil)
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.selfID.description == "003669928")
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.distressID.description == "338510241")
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.natureOfDistress == .manOverboard)
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.distressCoordinates.quadrant == .missing)
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.time.description == "23:00")
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.subsequentCommunications == DSCSymbol(symbol: 100)!)
        XCTAssert(distressAlertRelayAllShipsAcknowledgement.EOS == .providingAcknowledgement)
    }
    
    func testDSCUrgencyAndSafetyCalls() {
        let urgencyAndSafetyIndividualCallSymbols = [120,120,0,36,69,99,90,108,33,85,10,24,10,118,126,126,126,126,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        guard let urgencyAndSafetyIndividualCall = getDSCCall(callSymbols: urgencyAndSafetyIndividualCallSymbols) as? UrgencyAndSafetyCall else {
            print("urgencyAndSafetyIndividualCall did not get parsed to an UrgencyAndSafetyCall type.")
            return
        }
        XCTAssert(urgencyAndSafetyIndividualCall.formatSpecifier == .individualStationSelective)
        XCTAssert(urgencyAndSafetyIndividualCall.address?.description == "003669999")
        XCTAssert(urgencyAndSafetyIndividualCall.category == .safety)
        XCTAssert(urgencyAndSafetyIndividualCall.selfID.description == "338510241")
        XCTAssert(urgencyAndSafetyIndividualCall.firstTelecommand == .test)
        XCTAssert(urgencyAndSafetyIndividualCall.secondTelecommand == .noInformation)
        XCTAssert(urgencyAndSafetyIndividualCall.EOS == .acknowledgementRequired)
        
        let urgencyAndSafetyAllShipsCallSymbols = [116,116,110,33,85,10,24,10,118,126,126,126,126,126,126,126,127].map { DSCSymbol(symbol: $0)! }
        guard let urgencyAndSafetyAllShipsCall = getDSCCall(callSymbols: urgencyAndSafetyAllShipsCallSymbols) as? UrgencyAndSafetyCall else {
            print("urgencyAndSafetyAllShipsCall did not get parsed to an UrgencyAndSafetyCall type.")
            return
        }
        XCTAssert(urgencyAndSafetyAllShipsCall.formatSpecifier == .allShips)
        XCTAssert(urgencyAndSafetyAllShipsCall.address == nil)
        XCTAssert(urgencyAndSafetyAllShipsCall.category == .urgency)
        XCTAssert(urgencyAndSafetyAllShipsCall.selfID.description == "338510241")
        XCTAssert(urgencyAndSafetyAllShipsCall.firstTelecommand == .test)
        XCTAssert(urgencyAndSafetyAllShipsCall.secondTelecommand == .noInformation)
        XCTAssert(urgencyAndSafetyAllShipsCall.EOS == .other)
    }
    
    func testDSCRoutineCalls() {
        let routineIndividualCallSymbols = [120,120,24,73,65,0,0,100,24,73,65,0,0,100,126,90,0,6,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        guard let routineIndividualCall = getDSCCall(callSymbols: routineIndividualCallSymbols) as? RoutineCall else {
            print("routineIndividualCall did not get parsed to a RoutineCall type.")
            return
        }
        XCTAssert(routineIndividualCall.formatSpecifier == .individualStationSelective)
        XCTAssert(routineIndividualCall.address.description == "247365000")
        XCTAssert(routineIndividualCall.category == .routine)
        XCTAssert(routineIndividualCall.selfID.description == "247365000")
        XCTAssert(routineIndividualCall.firstTelecommand == .fmTelephony)
        XCTAssert(routineIndividualCall.secondTelecommand == .noInformation)
        XCTAssert(routineIndividualCall.frequency?.vhfChannelNumber?.0 == 6)
        XCTAssert(routineIndividualCall.EOS == .acknowledgementRequired)
        
        let routineGroupCallSymbols = [114,114,24,73,65,0,0,100,24,73,65,0,0,100,126,90,0,6,126,126,126,117].map { DSCSymbol(symbol: $0)! }
        guard let routineGroupCall = getDSCCall(callSymbols: routineGroupCallSymbols) as? RoutineCall else {
            print("routineGroupCall did not get parsed to a RoutineCall type.")
            return
        }
        XCTAssert(routineGroupCall.formatSpecifier == .commonInterestSelective)
        XCTAssert(routineGroupCall.address.description == "247365000")
        XCTAssert(routineGroupCall.category == .routine)
        XCTAssert(routineGroupCall.selfID.description == "247365000")
        XCTAssert(routineGroupCall.firstTelecommand == .fmTelephony)
        XCTAssert(routineGroupCall.secondTelecommand == .noInformation)
        XCTAssert(routineGroupCall.frequency?.vhfChannelNumber?.0 == 6)
        XCTAssert(routineGroupCall.EOS == .acknowledgementRequired)
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

