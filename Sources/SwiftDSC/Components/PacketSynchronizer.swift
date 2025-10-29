//
//  PacketSyncrhonizer.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/26/25.
//

import Accelerate
import Foundation
import SignalTools
import RTLSDRWrapper // for TimeOperation

// VHF DSC Dot Pattern: 0101... 20 bits
let DOT_PATTERN_CORRELATION_TEMPLATE: [Float] = {
    var pattern: [Float] = []
    for i in 0..<10 {
        pattern.append(-1)
        pattern.append(1)
    }
    return pattern
}()
let DSC_PHASING_SEQ_DX_SYMBOL = DSCSymbol(symbol: 125)!
let DX_PHASING_SEQUENCE: [DSCSymbol] = .init(repeating: DSC_PHASING_SEQ_DX_SYMBOL, count: 6)
let RX_PHASING_SEQUENCE: [DSCSymbol] = [DSCSymbol(symbol: 111)!, DSCSymbol(symbol: 110)!, DSCSymbol(symbol: 109)!, DSCSymbol(symbol: 108)!, DSCSymbol(symbol: 107)!, DSCSymbol(symbol: 106)!, DSCSymbol(symbol: 105)!, DSCSymbol(symbol: 104)!]
let EOS_SYMBOLS: [DSCSymbol] = [DSCSymbol(symbol: 117)!, DSCSymbol(symbol: 122)!, DSCSymbol(symbol: 127)!]


/// DSC-specific tool for finding the coarse & finer start of a DSC transmission.
package class VHFDSCPacketSynchronizer {
    var sampleRate: Int
    var samplesPerSymbol: Int { // Calculated based on VHF DSC baud of 1200
        sampleRate / 1200
    }
    var decoder: VHFDSCPacketDecoder
    
    var debugOutput: Bool
    
    init(sampleRate: Int, decoder: VHFDSCPacketDecoder, debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.decoder = decoder
        self.debugOutput = debugOutput
    }
    
    /// Will find the starting index of the VHF DSC dot pattern, '0101..' for 20 bits.
    /// **audio**: FM-demodulated samples.
    func findDotPatternStart(audio: [Float]) -> Int? {
        // Theory: For i = 0 ... samplesPerSymbol, calculate the bitstream starting from i. One of these will be at the correct offset to eventually decode the dot pattern, if present.
        // Afterwards, correlate each bitstream for the dot pattern, look for highest peak, this is the likely start
        let numOffsets = samplesPerSymbol
        var bitstreams: [[Float]] = Array(repeating: [], count: numOffsets)
        for i in 0..<numOffsets {
            let currSamples = Array(audio[i..<audio.count])
            if let (bitstream, _, _) = decoder.demodulateToBits(samples: currSamples) {
                bitstreams[i] = bitstream.asFloatArray()
            }
        }
        
        // Finding correlations for bits calculated from each offset.
        // Whichever has the highest correlation is likely aligned with bit boundaries properly.
        // Highest correlation location will be taken to be the beginning of the dot pattern.
        var correlations: [[Float]] = Array(repeating: [], count: numOffsets)
        for i in 0..<bitstreams.count {
            correlations[i] = slidingCorrelation(signal: bitstreams[i], template: DOT_PATTERN_CORRELATION_TEMPLATE) ?? []
        }
        var correlationIndicesAndValues: [(Int, Float)] = []
        for i in 0..<correlations.count {
            let currCorrelationIndicesAndValues = correlations[i].topKIndicesWithValues(2).map {
                ((samplesPerSymbol * $0.0) + i, $0.1)
            }
            correlationIndicesAndValues.append(contentsOf: currCorrelationIndicesAndValues)
        }
        correlationIndicesAndValues.sort { $0.1 > $1.1 } // Putting largest correlations first
        
        var likelyStartsAndConfidences: [(Int, Float)] = []
        for (index, _) in correlationIndicesAndValues {
            if let bitsFromIndex = decoder.demodulateToBits(samples: Array(audio[index..<(index + 20 * samplesPerSymbol)])) {
                let alternatingRate = alternatingRate(bitsFromIndex.0)
                if(alternatingRate > 0.85) {
                    likelyStartsAndConfidences.append((index, bitsFromIndex.1.average()))
                }
            }
        }
        likelyStartsAndConfidences.sort { $0.1 > $1.1 }
        return likelyStartsAndConfidences.first?.0
    }
    
    /// Given a dotPatternIndex, will try to find a starting sample that is aligned with the first symbol, 125.
    /// Therefore, decoding from this sample on, each (10 x samplesPerBit) samples will be a symbol in the message.
    func getPreciseStartingSample(audio: [Float], dotPatternIndex: Int) -> Int? {
        let maxSampleShift = Int(Double(self.samplesPerSymbol) * 1.5) // Maxmimum distance from dotPatternIndex to try shifting & redecoding.
        var potentialStarts: [(Int, Float)] = [] // Array of indexes from which starting here results in finding 125. Second element is average decision confidence.
        for shift in stride(from: -maxSampleShift, through: maxSampleShift, by: 1) {
            let potentialStartIndex = dotPatternIndex + shift
            guard potentialStartIndex >= 0 else { continue }
            let endSampleIndex = potentialStartIndex + (30 * samplesPerSymbol) // '125' should be in first 30 bits (20 dot pattern + 10 symbol)
            guard endSampleIndex < audio.count else { continue }
            let audioFromStart = Array(audio[potentialStartIndex..<endSampleIndex])
            guard let (bitsFromStart, confidences, _) = self.decoder.demodulateToBits(samples: audioFromStart) else { continue }
            let bitstringFromStart = bitsFromStart.getBitstring()
//            debugPrint("\(shift): \(bitstringFromStart)")
            guard let indexRangeOfStartSymbol = bitstringFromStart.range(of: "1011111001") else { continue }
            let numberOfSamplesToSkip = bitstringFromStart.distance(from: bitstringFromStart.startIndex, to: indexRangeOfStartSymbol.lowerBound) * samplesPerSymbol
            potentialStarts.append(((dotPatternIndex + shift + numberOfSamplesToSkip), confidences.average()))
        }
        
        potentialStarts.sort { $0.1 > $1.1 } // Sorting by confidence, descending from index 0.
        return potentialStarts.first?.0
    }
    
    /// Checks if lock has been acquired -- meaning full phasing sequence has been recieved.
    /// Worth noting that matcing *all* symbols is significantly stricter than what the spec calls for
    func lockIsAcquired(dx: [DSCSymbol], rx: [DSCSymbol]) -> Bool {
        guard dx.count >= 8 && rx.count >= 8 else { return false } // Phasing sequence occupies first 16 symbols
        let relevantDX = Array(dx[0..<6])
        let relevantRX = Array(rx[0..<8])
        return relevantDX == DX_PHASING_SEQUENCE && relevantRX == RX_PHASING_SEQUENCE
    }
    
    /// Checks if dx has any of the EOS symbols.
    func reachedEndSequence(dx: [DSCSymbol]) -> Bool {
        return dx.contains(where: { symbol in EOS_SYMBOLS.contains(symbol)})
    }
    
    /// Checks if full DSC message has been received. If it has, returns the error checking character. Otherwise nil.
    func checkIfComplete(dx: [DSCSymbol], rx: [DSCSymbol]) -> DSCSymbol? {
        guard let eosSymbolIndex = dx.firstIndex(where: { symbol in EOS_SYMBOLS.contains(symbol)}) else { return nil }
        let eosSymbol = dx[eosSymbolIndex]
        let eosCount = dx.count(where: {$0 == eosSymbol})
        if eosCount < 3 {
            debugPrint("Warning: there are less than three eos (\(eosSymbol)) symbols in this call. It is either not fully received, or malformed.")
        }
        let errorCheckSymbol = dx[eosSymbolIndex + 1]
        return errorCheckSymbol
    }
    
    private func getSignificantExtremaIndicies(angle: [Float], useMax: Bool = true) -> [Int] {
        let indicies = useMax ? angle.localMaximaIndicies() : angle.localMinimaIndicies()
        return indicies.filter {
            abs(angle[$0]) > (Float.pi / 2 - 1)
        }
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print("Synchronizer: " + str)
        }
    }
    
}

private func alternatingRate(_ bits: BitBuffer) -> Float {
    guard bits.count > 1 else { return 0.0 }
    var alternateCount: Int = 0
    for i in 1..<bits.count {
        if(bits[i] != bits[i-1]) {
            alternateCount += 1
        }
    }
    return Float(alternateCount) / Float(bits.count - 1)
}

