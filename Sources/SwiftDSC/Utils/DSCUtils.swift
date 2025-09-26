//
//  DSCConstants.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/19/25.
//
import Foundation



public struct MMSI {
    var value: UInt32
    
    init?(symbols: [DSCSymbol]) {
        guard symbols.count == 5 else {
            print("Improper number of symbols provided for MMSI (\(symbols.count), expected 5)")
            return nil
        }
        var mmsiValue: UInt32 = 0
        for (index, symbol) in symbols.enumerated() {
            guard let symbolValue = symbol.symbol else { return nil }
            let symbolValAsDouble = Double(symbolValue)
            let shiftValueExponent = 7.0 - (2.0 * Double(index))
            let shiftValue = pow(10, shiftValueExponent)
            mmsiValue += UInt32(shiftValue * symbolValAsDouble)
        }
        //mmsiValue = mmsiValue / 10 // Removes trailing 0
        self.value = mmsiValue
    }
    
    var description: String {
        var mmsiString = String(self.value)
        if mmsiString.count < 9 {
            let paddingCount = 9 - mmsiString.count
            mmsiString = String(repeating: "0", count: paddingCount) + mmsiString
        }
        return mmsiString
    }
}

public struct DSCTime {
    let hours: UInt8
    let minutes: UInt8
    let digitString: String
    
    public init?(symbols: [DSCSymbol]) {
        guard symbols.count == 2 else {
            print("Improper number of symbols provided for DSCTime, \(symbols.count), expected 2")
            return nil
        }
        guard let hrs = symbols[0].symbol, let mins = symbols[1].symbol else {
            print("Nil provided in hours or minutes position for DSCTime.")
            return nil
        }
        self.hours = hrs
        self.minutes = mins
        self.digitString = "\(hrs)\(mins)"
    }
    
}

// Convenience wrapper struct for coordinates which are provided by some message formats.
public struct DSCCoordinates {
    let quadrant: DSCQuadrant
    let latitudeDegrees: Int
    let latitudeMinutes: Int
    let longitudeDegrees: Int
    let longitudeMinutes: Int
    let digitString: String
    
    public init?(symbols: [DSCSymbol]) {
        guard symbols.count == 5 else {
            print("Improper number of symbols provided for DSCCoordinates (\(symbols.count), expected 5")
            return nil
        }
        guard let quadrant = DSCQuadrant(symbol: symbols[0]) else {
            print("Improper quadrant number (\(String(describing: symbols[0].symbol)) provided, expected 0-3")
            return nil
        }
        self.quadrant = quadrant
        guard let digits = symbolsToDigitString(symbols) else {
            print("Unable to convert symbols to 10-digit string for DSCCordinates.")
            return nil
        }
        self.digitString = digits
        let latitudeStartIndex = digits.index(digits.startIndex, offsetBy: 1)
        guard let latDegrees = Int(String(digits[latitudeStartIndex..<digits.index(latitudeStartIndex, offsetBy: 2)])), let latMinutes = Int(String(digits[digits.index(latitudeStartIndex, offsetBy: 2)..<digits.index(latitudeStartIndex, offsetBy: 4)])) else {
            print("Unable to convert latitude digits to Int")
            return nil
        }
        self.latitudeDegrees = latDegrees
        self.latitudeMinutes = latMinutes
        
        let longitudeStartIndex = digits.index(digits.startIndex, offsetBy: 5)
        guard let longDegrees = Int(String(digits[longitudeStartIndex..<digits.index(longitudeStartIndex, offsetBy: 3)])), let longMinutes = Int(String(digits[digits.index(longitudeStartIndex, offsetBy: 2)..<digits.index(longitudeStartIndex, offsetBy: 4)])) else {
            print("Unable to convert longitude digits to Int")
            return nil
        }
        self.longitudeDegrees = longDegrees
        self.longitudeMinutes = longMinutes
    }
    
}

// Converts 5 symbols to a 10-digit number as a string, including leading zeroes.
// Designed according to table A1-2 from ITU-R M.493-16
func symbolsToDigitString(_ symbols: [DSCSymbol]) -> String? {
    var digits: UInt16 = 0
    for (index, symbol) in symbols.enumerated() {
        guard let symbolValue = symbol.symbol else { return nil }
        let symbolValAsDouble: Double = Double(symbolValue)
        let shiftValueExponent = 8.0 - (2 * Double(index))
        let shiftValue = pow(10.0, shiftValueExponent)
        digits += UInt16(shiftValue * symbolValAsDouble)
    }
    var digitsString = String(digits)
    if digitsString.count < 10 {
        digitsString = String(repeating: "0", count: 10 - digitsString.count) + digitsString
    }
    return digitsString
}

package enum DSCError: Error {
    case invalidSymbol
}

public struct DSCSymbol: Equatable {
    var code: UInt16
    var codeBinaryString: String
    var symbol: UInt8?
    var codeIsValid: Bool { symbol != nil }
    
    init(code: UInt16) {
        self.code = code
        let symbol = DSC_CODE_TO_SYMBOL[code]
        self.symbol = symbol
        self.codeBinaryString = stringifyDSCCode(code)
    }
    
    init?(symbol: UInt8) {
        guard let code = DSC_SYMBOL_TO_CODE[symbol] else { return nil }
        self.code = code
        self.symbol = symbol
        self.codeBinaryString = stringifyDSCCode(code)
    }
    
    public static func == (lhs: DSCSymbol, rhs: DSCSymbol) -> Bool {
        return lhs.code == rhs.code
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
