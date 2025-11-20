//
//  DSCConstants.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 8/19/25.
//
import Foundation

enum ModulationType: String {
    case f1b = "FSK"
    case j2b = "SSB Modulated AFSK"
    case j3e = "SSB Voice - Suppressed Carrier"
    case f3e = "FM Voice"
}

/// DSC Message 2, in various call formats, is used for transmitting frequencies for subsequent communications.
/// The spec refers to it as a "frequency message", but it actually can contain two different frequencies within it.
/// Including a second frequency or an MF/HF channel number seems to imply the use of duplex radiotelephony -- facilitating calls between ship & shore stations. It appears that as of 2025, this is a thing of the past, and it's likely this feature can't be tested in the real-world.
/// Certain VHF channels are being renamed with 4-digit names by 2030. It's unclear how this will work via DSC, as it can only transmit VHF frequencies with 3 digits.
public struct DSCFrequency {
    var txFrequency: Int?
    var rxFrequency: Int?
    
    /// For channels, storing two values:
    /// Element 0: Called station Rx channel number
    /// Element 1: Called station Tx channel number
    var vhfChannelNumber: (Int?,Int?)?
    var mfHfChannelNumber: (Int?,Int?)?
    
    init?(symbols: [DSCSymbol]) {
        guard symbols.count == 6 || symbols.count == 8 else {
            print("Improper number of symbols provided for DSC frequency (\(symbols.count), expected 6 or 8.)")
            return nil
        }
        let useFourSymbols = symbols.count == 8
        
        // Rx Field
        let rxFreqResult: (Int, Int)? = useFourSymbols ? get4CharFreq(symbols: Array(symbols[0..<4])) : get3CharFreq(symbols: Array(symbols[0..<3]))
        if let rxFreqResult = rxFreqResult {
            if(rxFreqResult.1 == -1) {
                rxFrequency = rxFreqResult.0
            }
            else if(rxFreqResult.1 == 0) {
                vhfChannelNumber = (nil,nil)
                vhfChannelNumber!.0 = rxFreqResult.0
            }
            else if(rxFreqResult.1 == 1) {
                mfHfChannelNumber = (nil,nil)
                mfHfChannelNumber!.0 = rxFreqResult.0
            }
            else {
                print("Got an unexpected value in rxFreqResult.1 (\(rxFreqResult.1))")
                return nil
            }
        }
        
        // Tx Field
        let txFreqResult: (Int, Int)? = useFourSymbols ? get4CharFreq(symbols: Array(symbols[4..<8])) : get3CharFreq(symbols: Array(symbols[3..<6]))
        if let txFreqResult = txFreqResult {
            if(txFreqResult.1 == -1) {
                txFrequency = txFreqResult.0
            }
            else if(txFreqResult.1 == 0) {
                if(vhfChannelNumber == nil) {
                    vhfChannelNumber = (nil,nil)
                }
                vhfChannelNumber!.1 = txFreqResult.0
            }
            else if(txFreqResult.1 == 1) {
                if(vhfChannelNumber == nil) {
                    mfHfChannelNumber = (nil,nil)
                }
                mfHfChannelNumber!.1 = txFreqResult.0
            }
            else {
                print("Got an unexpected value in txFreqResult.1 (\(txFreqResult.1))")
                return nil
            }
        }
    }
    
    /// Gets frequency or channel number from 3 symbols.
    /// This can be used to describe a VHF channel, or a frequency in 100Hz units.
    /// Returns a set with two elements:
    /// Element 0: The frequency in **Hz**, or a channel number as indicated by element 1.
    /// Element 1: 0 if 0th element of return value is a VHF channel number, 1 if MF/HF channel number, -1 if not a channel number.
    func get3CharFreq(symbols: [DSCSymbol]) -> (Int, Int)? {
        guard symbols.count == 3 else {
            print("Improper number of symbols passed to getFreq (\(symbols.count), expected 3")
            return nil
        }
        guard let char3 = symbols[0].symbol, let char2 = symbols[1].symbol, let char1 = symbols[2].symbol else { return nil }
        guard char3 != 126 && char2 != 126 && char1 != 126 else { return nil }
        let HM = Int(char3 / 10)
        let TM = Int(char3 % 10)
        let M = Int(char2 / 10)
        let H = Int(char2 % 10)
        let T = Int(char1 / 10)
        let U = Int(char1 % 10)
        if(HM == 9) {
            // If HM is 9, it's a VHF channel number.
            // VHF Channel Num = H T U
            let channelNum: Int = (H * 100) + (T * 10) + U
            return (channelNum, 0)
        }
        else if(HM == 3) {
            // If HM is 3, it's an MF/HF channel number.
            // MF/HF Channel Num = TM M H T U
            let channelNum: Int = (TM*10000) + (M*1000) + (H*100) + (T*10) + U
            return (channelNum, 1)
        }
        else {
            let frequency = (HM * 100000) + (TM * 10000) + (M * 1000) + (H * 100) + (T * 10) + U
            return (frequency, -1)
        }
    }
    
    /// Gets frequency from 4 symbols.
    /// Used to describe a 7-digit frequency (ex.
    /// Returns a set with two elements (nil if unsuccessful or no freq. provided):
    /// Element 0: Frequency in **Hz**
    /// Element 1: Unused; just here to keep same type signature as get3CharFreq.
    func get4CharFreq(symbols: [DSCSymbol]) -> (Int, Int)? {
        guard let char3 = symbols[0].symbol, let char2 = symbols[1].symbol, let char1 = symbols[2].symbol, let char0 = symbols[3].symbol else { return nil }
        guard char3 != 126 && char2 != 126 && char1 != 126 && char0 != 126 else { return nil }
        let _ = Double(char3 / 10) // HM is just a placeholder of '4' in the spec
        let TM = Double(char3 % 10)
        let M = Double(char2 / 10)
        let H = Double(char2 % 10)
        let T = Double(char1 / 10)
        let U = Double(char1 % 10)
        let T1 = Double(char0 / 10)
        let U1 = Double(char0 % 10)
        
        return (Int(((TM * 10000) + (M * 1000) + (H * 100) + (T * 10.0) + U + (0.1 * T1) + (0.01 * U1)) * 1000), -1) // Transmitted OTA as KHz
    }
    
    var description: String {
        var fullString: String = ""
        
        if let vhfChannels = self.vhfChannelNumber {
            if let vhfRxChannel = vhfChannels.0 {
                fullString += "RX: VHF Channel \(vhfRxChannel)"
            } else {
                fullString += "RX: Channel Unspecified"
            }
            
            fullString += " "
            
            if let vhfTxChannel = vhfChannels.1 {
                fullString += "TX: VHF Channel \(vhfTxChannel)"
            } else {
                fullString += "TX: Channel Unspecified"
            }
        }
        
        else if let mfhfChannels = self.mfHfChannelNumber {
            if let mfhfRxChannel = mfhfChannels.0 {
                fullString += "RX: MF/HF Channel \(mfhfRxChannel)"
            } else {
                fullString += "RX: Channel Unspecified"
            }
            
            fullString += " "
            
            if let mfhfTxChannel = mfhfChannels.1 {
                fullString += "TX: MF/HF Channel \(mfhfTxChannel)"
            } else {
                fullString += "TX: Channel Unspecified"
            }
        }
        
        else {
            if let rxFrequency = self.rxFrequency {
                fullString += "RX: \(Double(rxFrequency) / 1000) KHz"
            } else {
                fullString += "RX: Frequency Unspecified"
            }
            
            fullString +=  " "
            
            if let txFrequency = self.txFrequency {
                fullString += "TX: \(Double(txFrequency) / 1000) KHz"
            } else {
                fullString += "TX: Frequency Unspecified"
            }
        }
        
        return fullString
    }
    
}

/// Struct for creating an MMSI (Maritime Mobile Service Identity) from 5 symbols as provided by some DSC call formats.
/// MMSI should always be 9 digits.
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
    }
    
    var description: String {
        return String(format: "%02d:%02d", hours, minutes)
    }
}

/// Struct for coordinates which are provided by some message formats.
/// Spec refers to this as Pos1
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
        if(quadrant == .missing) {
            self.latitudeDegrees = 0
            self.latitudeMinutes = 0
            self.longitudeDegrees = 0
            self.longitudeMinutes = 0
            digitString = ""
            return
        }
        
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
    
    var description: String {
        if(quadrant == .missing) { return "Missing Coordinates" }
        
        let latDirection: String
        let longDirection: String
        
        switch quadrant {
        case .NE:
            latDirection = "N"
            longDirection = "E"
        case .NW:
            latDirection = "N"
            longDirection = "W"
        case .SE:
            latDirection = "S"
            longDirection = "E"
        case .SW:
            latDirection = "S"
            longDirection = "W"
        default:
            return "Missing Coordinates"
        }
        
        let latDegStr = String(format: "%02d", latitudeDegrees)
        let latMinStr = String(format: "%02d", latitudeMinutes)
        
        // Longitude degrees can be up to 3 digits (000 to 180)
        let longDegStr = String(format: "%03d", longitudeDegrees)
        // Longitude minutes should be 2 digits
        let longMinStr = String(format: "%02d", longitudeMinutes)
        
        // Example format: 45° 30' N, 120° 15' W
        return "\(latDegStr)° \(latMinStr)' \(latDirection), \(longDegStr)° \(longMinStr)' \(longDirection)"
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

/// DSC "Symbols" are the base components of a DSC call.
/// Depending on what position they are in, they can have various meanings, as prescribed in DSCSymbolEnums.
public struct DSCSymbol: Equatable {
    var code: UInt16 // 10-bit code, first 7 bits are information, containing the value reversed. Last 3 bits are the count of zeroes in the information bits.
    var codeBinaryString: String
    var symbol: UInt8?
    var codeIsValid: Bool { symbol != nil }
    
    /// Init a DSCSymbol from 10-bit code.
    /// Note: This will never return nil, but, if **code** is not a valid 10-bit code, then **symbol** will be nil.
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

package let VHF_DSC_CENTER_FREQUENCY = 156525000 // VHF Channel 70
