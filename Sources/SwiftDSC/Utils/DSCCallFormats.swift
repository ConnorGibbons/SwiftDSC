//
//  CallFormats.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/19/25.
//
import Foundation

public protocol DSCCall {
    var formatSpecifier: DSCFormatSpecifier { get }
    var selfID: MMSI { get }
    var EOS: DSCEOSSymbol { get }
    var description: String { get }
}

public func getDSCCall(callSymbols: [DSCSymbol]) -> DSCCall? {
    guard callSymbols.count >= 16 else { // Shortest call seems to be Distress Alert at 16 symbols.
        print("Call too short to be valid: \(callSymbols.count)")
        return nil
    }
    guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[0]) else {
        print("Invalid format specifier: \(callSymbols[0])")
        return nil
    }
    guard let eos = DSCEOSSymbol(symbol: callSymbols.last!) else {
        print("Invalid EOS symbol: \(callSymbols.last!)")
        return nil
    }
    
    if(formatSpecifier == .distressAlert) { // Distress Alert is the only call type with this format specifier (112)
        return DistressAlert(callSymbols: callSymbols)
    }
    else if(formatSpecifier == .allShips && DSCCategory(symbol: callSymbols[2]) == .distress && DSCFirstTelecommand(symbol: callSymbols[8]) == .distressAcknowledgement) {
        return DistressAcknowledgement(callSymbols: callSymbols)
    }
    else if(DSCCategory(symbol: callSymbols[7]) == .distress && DSCFirstTelecommand(symbol: callSymbols[13]) == .distressAlertRelay && (eos == .acknowledgementRequired || eos == .other)) {
        return DistressAlertRelay(callSymbols: callSymbols)
    }
    else if(DSCCategory(symbol: callSymbols[7]) == .distress && DSCFirstTelecommand(symbol: callSymbols[13]) == .distressAlertRelay && eos == .providingAcknowledgement) {
        return DistressAlertRelayAcknowledgement(callSymbols: callSymbols)
    }
    else if(DSCCategory(symbol: callSymbols[7]) == .safety || DSCCategory(symbol: callSymbols[7]) == .urgency) {
        return UrgencyAndSafetyCall(callSymbols: callSymbols)
    }
    else if(DSCCategory(symbol: callSymbols[7]) == .routine) {
        return RoutineCall(callSymbols: callSymbols)
    }
    else {
        print("Unrecognized call sequence.")
        return nil
    }
}

// Distress Alerts
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Self-ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAlert: DSCCall {
    public var description: String
    
    // Shared
    public let formatSpecifier: DSCFormatSpecifier = .distressAlert
    public let selfID: MMSI
    public let EOS: DSCEOSSymbol = .other
    
    // Distress Specific
    public let natureOfDistress: DSCDistressNature // Message 1
    public let distressCoordinates: DSCCoordinates // Message 2
    public let timeUTC: DSCTime // Message 3
    public let subsequentCommunications: DSCSymbol // Message 4 -- supposed to be 100 (VHF) or 109 (MF/HF)
    
    init?(callSymbols: [DSCSymbol]) {
        return nil
    }
    
}

// Distress Alert Acknowledgements -- Sent by distress alert recipients.
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Category<1> --> Self-ID<5> --> Telecommand<1> --> Distress ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAcknowledgement: DSCCall {
    public var description: String
    
    // Shared
    public let formatSpecifier: DSCFormatSpecifier = .allShips
    public let selfID: MMSI
    public let EOS: DSCEOSSymbol = .other
    
    // Distress Ack Specific
    public let category: DSCCategory = .distress
    public let telecommand: DSCFirstTelecommand = .distressAcknowledgement
    public let distressID: MMSI // Message 0
    public let natureOfDistress: DSCDistressNature // Message 1
    public let distressCoordinates: DSCCoordinates // Message 2
    public let timeUTC: DSCTime // Message 3
    public let subsequentCommunications: DSCSymbol // Message 4
    
    init?(callSymbols: [DSCSymbol]) {
        return nil
    }
}

// Distress Alert Relay
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Address<5> --> Category<1> --> Self-ID<5> --> Telecommand<1> --> Distress ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAlertRelay: DSCCall {
    public var description: String
    
    // Shared
    public let formatSpecifier: DSCFormatSpecifier // Can be 120, 114, 102, 116
    public let selfID: MMSI
    public let EOS: DSCEOSSymbol // 117 or 127
    
    // Distress Alert Relay Specific
    public let address: MMSI? // Not present if addressed to all ships (116 format specifier)
    public let category: DSCCategory = .distress
    public let telecommand: DSCFirstTelecommand = .distressAlertRelay
    public let distressID: MMSI // Message 0
    public let natureOfDistress: DSCDistressNature // Message 1
    public let distressCoordintaes: DSCCoordinates // Message 2
    public let time: DSCTime // Message 3
    public let subsequentCommunications: DSCSymbol // Message 4 -- valid values are 100, 109, 126
    
    init?(callSymbols: [DSCSymbol]) {
        return nil
    }
}

// Distress Alert Relay Acknowledgement
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Address<5> --> Category<1> --> Self-ID<5> --> Telecommand<1> --> Distress ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAlertRelayAcknowledgement: DSCCall {
    public var description: String
    
    // Shared
    public let formatSpecifier: DSCFormatSpecifier // Can be 120, 114, 116
    public let selfID: MMSI
    public let EOS: DSCEOSSymbol = .providingAcknowledgement
    
    // Distress Alert Relay Ack. Specific
    public let address: MMSI? // Not present if addressed to all ships (116 format specifier)
    public let category: DSCCategory = .distress
    public let telecommand: DSCFirstTelecommand = .distressAlertRelay
    public let distressID: MMSI // Message 0
    public let natureOfDistress: DSCDistressNature // Message 1
    public let distressCoordinates: DSCCoordinates // Message 2
    public let time: DSCTime // Message 3
    public let subsequentCommunications: DSCSymbol // Message 4
    
    init?(callSymbols: [DSCSymbol]) {
        return nil
    }
}

// Urgency and Safety calls
// Can be made to all ships (116), one station (120), or to an area (102).
// Spec implies that area calls can only be made via MF/HF.
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Address<5> --> Category<1> --> Self-ID<5> --> 1st Telecommand<1> --> 2nd Telecommand<1> --> Frequency/Pos<6 / 8>
public struct UrgencyAndSafetyCall: DSCCall {
    // Shared
    public let formatSpecifier: DSCFormatSpecifier // Can be 102, 116, or 120
    public let selfID: MMSI
    public let EOS: DSCEOSSymbol // All are valid here -- depends on context.
    
    // Urgency and Safety Call Specific
    public let address: MMSI
    public let category: DSCCategory // 108 or 110
    public let firstTelecommand: DSCFirstTelecommand // Message 1 (part 1)
    public let secondTelecommand: DSCSecondTelecommand // Message 1 (part 2)
    // Message 2 can be either Frequency or Position -- need to make something for this
    public let time: DSCTime? // Message 3 (Only in position acknowledgements)
    
    init?(callSymbols: [DSCSymbol]) {
        guard callSymbols.count >= 21 else {
            print("callSymbols too short for UrgencyAndSafety (\(callSymbols.count)), expected 21-23")
            return nil
        }
        
        guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[0]) else {
            print("First symbol is not a valid format specifier.")
            return nil
        }
        self.formatSpecifier = formatSpecifier
        
        guard let address = MMSI(symbols: Array(callSymbols[2..<7])) else {
            print("Could not parse symbols as MMSI.")
            return nil
        }
        self.address = address
        
        guard let category = DSCCategory(symbol: callSymbols[7]) else {
            print("Could not parse category symbol.")
            return nil
        }
        guard category == .urgency || category == .safety else {
            print("Invalid category for UrgencyAndSafetyCall: \(category)")
            return nil
        }
        self.category = category
        guard let selfID = MMSI(symbols: Array(callSymbols[8..<13])) else {
            print("Could not parse symbols as MMSI (selfID)")
            return nil
        }
        self.selfID = selfID
        
        guard let firstTelecommand = DSCFirstTelecommand(symbol: callSymbols[13]) else {
            print("Invalid first telecommand: \(callSymbols[13])")
            return nil
        }
        self.firstTelecommand = firstTelecommand
        
        guard let secondTelecommand = DSCSecondTelecommand(symbol: callSymbols[14]) else {
            print("Invalid second telecommand: \(callSymbols[14])")
            return nil
        }
        self.secondTelecommand = secondTelecommand
        
        guard let eos = DSCEOSSymbol(symbol: callSymbols.last!) else {
            print("Invalid EOS Symbol \(callSymbols.last!)")
            return nil
        }
        self.EOS = eos
        
        self.time = nil
    }
    
    public var description: String {
        let prefix = self.category == .safety ? "SAFETY" : "URGENCY"
        let selfID = selfID.description
        let address = address.description
        let commandOne = firstTelecommand.description
        let commandTwo = secondTelecommand.description
        let eos = EOS.description
        
        return "\(NSDate().description) - [\(prefix)]: \(selfID) to \(address) - 1st Command: \(commandOne) 2nd Command: \(commandTwo) - \(eos)"
    }
}


// Routine Calls
// Can be made to groups (114) or individual stations (120)
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Address<5> --> Category<1> --> Self-ID<5> --> 1st Telecommand<1> --> 2nd Telecommand<1> --> Frequency/Pos<6 / 8>
public struct RoutineCall: DSCCall {
    // Shared
    public let formatSpecifier: DSCFormatSpecifier  // 114 or 120
    public let selfID: MMSI
    public let EOS: DSCEOSSymbol // All are valid here -- depends on context.
    
    // Routine Call Specific
    public let address: MMSI
    public let category: DSCCategory = .routine
    public let firstTelecommand: DSCFirstTelecommand // Message 1 (part 1)
    public let secondTelecommand: DSCSecondTelecommand // Message 1 (part 2)
    // Message 2 can be either Frequency or Position -- need to make something for this
    
    init?(callSymbols: [DSCSymbol]) {
        guard callSymbols.count >= 21 else {
            print("callSymbols too short for RoutineCall (\(callSymbols.count)), expected 21-23")
            return nil
        }
        
        guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[0]) else {
            print("First symbol is not a valid format specifier.")
            return nil
        }
        self.formatSpecifier = formatSpecifier
        
        guard let address = MMSI(symbols: Array(callSymbols[2..<7])) else {
            print("Could not parse symbols as MMSI.")
            return nil
        }
        self.address = address
        
        guard let category = DSCCategory(symbol: callSymbols[7]) else {
            print("Could not parse category symbol.")
            return nil
        }
        guard category == .routine else {
            print("Invalid category for RoutineCall: \(category)")
            return nil
        }
        
        guard let selfID = MMSI(symbols: Array(callSymbols[8..<13])) else {
            print("Could not parse symbols as MMSI (selfID)")
            return nil
        }
        self.selfID = selfID
        
        guard let firstTelecommand = DSCFirstTelecommand(symbol: callSymbols[13]) else {
            print("Invalid first telecommand for RoutineCall: \(callSymbols[13])")
            return nil
        }
        self.firstTelecommand = firstTelecommand
        
        guard let secondTelecommand = DSCSecondTelecommand(symbol: callSymbols[14]) else {
            print("Invalid second telecommand for RoutineCall: \(callSymbols[14])")
            return nil
        }
        self.secondTelecommand = secondTelecommand
        
        guard let eos = DSCEOSSymbol(symbol: callSymbols.last!) else {
            print("Invalid EOS Symbol \(callSymbols.last!)")
            return nil
        }
        self.EOS = eos
    }
    
    public var description: String {
        let selfID = selfID.description
        let address = address.description
        let commandOne = firstTelecommand.description
        let commandTwo = secondTelecommand.description
        let eos = EOS.description
        
        return "\(NSDate().description) - [ROUTINE]: \(selfID) to \(address) - 1st Command: \(commandOne) 2nd Command: \(commandTwo) - \(eos)"
    }
}
