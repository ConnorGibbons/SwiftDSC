//
//  PacketDecoder.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/26/25.
//

// Extracts bit-level info from DSC packet samples

import Foundation
import SignalTools
import Accelerate

/// PacketDecoder for VHF DSC packets -- frequency modulated AFSK.
/// Uses AFSK demodulator from SignalTools
package class VHFDSCPacketDecoder {
    var sampleRate: Int
    var samplesPerSymbol: Int {
        sampleRate / 1200
    }
    let markCoeff: Float
    let spaceCoeff: Float
    
    var debugOutput: Bool
    
    init(sampleRate: Int, isVHF: Bool = true, debugOutput: Bool = false) {
        self.sampleRate = sampleRate
        self.debugOutput = debugOutput
        self.markCoeff = getGoertzelCoeff(targetFrequency: 1300, sampleRate: sampleRate)
        self.spaceCoeff = getGoertzelCoeff(targetFrequency: 2100, sampleRate: sampleRate)
    }
    
    /// Decodes DSCSymbol array from samples .
    /// The 'samples' input should be FM-demodulated, not raw IQ.
    /// Returns an optional tuple (nil if demodulation failed):
    /// Element 0: [DSCSymbol] containing each decoded symbol.
    /// Element 1: [Float] containing the remainder samples that weren't used to determine a bit. Should be stored and prepended to future samples to avoid timing error / missing bits.
    func decodeToSymbols(samples: [Float], context: inout BitBuffer) -> ([DSCSymbol], [Float])? {
        guard let (bits, _, leftoverSamples) = demodulateToBits(samples: samples) else { return nil }
        var resultSymbols: [DSCSymbol] = []
        var currBitstring: String = context.getBitstring()
        context = BitBuffer()
        for i in 0..<bits.count {
            currBitstring.append(String(bits[i]))
            if(currBitstring.count == 10) {
                let asUInt16: UInt16 = UInt16(currBitstring, radix: 2) ?? 0
                resultSymbols.append(DSCSymbol(code: asUInt16))
                currBitstring = ""
            }
        }
        for bit in currBitstring { // Adding remaining bits to context
            bit == "0" ? context.append(0) : context.append(1)
        }
        return (resultSymbols, leftoverSamples)
    }
    
    /// Demodulates audio samples to bits using AFSK demodulation.
    /// Returns an optional tuple (nil if demodulation failed):
    /// Element 0: BitBuffer containing demodulated bits.
    /// Element 1: [Float] containing the confidence rating for each bit decision.
    /// Element 2: [Float] containing the remainder samples that weren't used. (Leftover after last bit decision is made, and not enough samples to decide next bit)
    func demodulateToBits(samples: [Float]) -> (BitBuffer, [Float], [Float])? {
        guard let (demodulatedBits, confidenceArray) = afskDemodulate(samples: samples, sampleRate: self.sampleRate, baud: 1200, markCoeff: markCoeff, spaceCoeff: spaceCoeff) else { return nil }
        let leftoverCount = samples.count % Int(self.sampleRate / 1200)
        let leftoverSamples = leftoverCount == 0 ? [] : Array(samples[samples.count - leftoverCount ..< samples.count])
        return (demodulatedBits, confidenceArray, leftoverSamples)
    }
    
    /// Prints only if self.debugOutput is true.
    private func debugPrint(_ str: String) {
        if(self.debugOutput) {
            print("Packet Decoder: " + str)
        }
    }
    
}
