//
//  DSCConstants.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/19/25.
//

package enum DSCError: Error {
    case invalidSymbol
}

package struct DSCSymbol {
    var code: UInt16
    var codeBinaryString: String
    var symbol: UInt8
    
    init(code: UInt16) throws {
        self.code = code
        guard let symbol = DSC_CODE_TO_SYMBOL[code] else { throw DSCError.invalidSymbol }
        self.symbol = symbol
        self.codeBinaryString = stringifyDSCCode(code)
    }
}

package func reverseBits(_ n: UInt8) -> UInt8 {
    var reversed: UInt8 = 0
    var nCopy = n
    for _ in 0..<8 {
        reversed = reversed << 1
        reversed |= (nCopy & 1)
        nCopy >>= 1
    }
    return reversed
}

/// Maps a UInt8 ('symbol') to the corresponding DSC 10-bit code.
/// 10-bit code will be returned as UInt16 where the highest 6 bits are 0.
/// Inputs where the highest bit is '1' are not valid as DSC only uses 7 information bits.
package func encodeSymbolDSC(_ symbol: UInt8) -> UInt16? {
    guard symbol < 128 else { return nil }
    let zeroCount = 7 - symbol.nonzeroBitCount
    let reversed = reverseBits(symbol) >> 1
    let encodedSymbol: UInt16 = UInt16(reversed) << 3 | UInt16(zeroCount)
    return encodedSymbol
}

package func stringifyDSCCode(_ code: UInt16) -> String {
    return String(code, radix: 2)
}

package let DSC_SYMBOL_TO_CODE: [UInt8: UInt16] = {
    var result: [UInt8: UInt16] = [:]
    for i in 0..<128 {
        if let encodedSymbol = encodeSymbolDSC(UInt8(i)) {
            result[UInt8(i)] = encodedSymbol
        }
    }
    return result
}()

package let DSC_CODE_TO_SYMBOL: [UInt16: UInt8] = DSC_SYMBOL_TO_CODE.reduce([:], { result, nextPartialResult in
    var newResult = result
    newResult[nextPartialResult.value] = nextPartialResult.key
    return newResult
})
