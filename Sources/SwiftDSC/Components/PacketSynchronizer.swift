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
    /// If unable to find a sequence where alternating rate  >0.85, returns nil. 
    func findDotPatternStart(audio: [Float]) -> Int? {
        var bestConfidence = -Float.infinity
        var bestConfidenceIndex: Int?
        for i in 0..<(audio.count - (20 * samplesPerSymbol)) {
            var timeDemodulate = TimeOperation.init(operationName: "Demodulation (20 bits)")
            if let (bits, confidenceArray) = self.decoder.demodulateToBits(samples: Array(audio[i..<i+(20 * samplesPerSymbol)])) {
                //print(timeDemodulate.stop())
                var timeAlternating = TimeOperation.init(operationName: "Alternating check (20 bits)")
                let alternatingRate = alternatingRate(bits)
                //print(timeAlternating.stop())
                if(alternatingRate > 0.9) {
                    //print("rate > 0.9")
                    let averageConfidence = confidenceArray.average()
                    if(averageConfidence > bestConfidence) {
                        bestConfidence = averageConfidence
                        bestConfidenceIndex = i
                    }
                }
            } else { continue }
        }
        return bestConfidenceIndex
    }
    
    func getPreciseStartingSample(angle: [Float], offset: Int) -> Int {
        return -1
    }
    
    private func getSignificantExtremaIndicies(angle: [Float], useMax: Bool = true) -> [Int] {
        let indicies = useMax ? angle.localMaximaIndicies() : angle.localMinimaIndicies()
        return indicies.filter {
            abs(angle[$0]) > (Float.pi / 2 - 1)
        }
    }
    
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print(str)
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

