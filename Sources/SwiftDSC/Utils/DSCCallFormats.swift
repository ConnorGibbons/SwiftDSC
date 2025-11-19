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

/// Given a callSymbols array, will dispatch to the correct DSCCall struct and return an instance, or nil if it does not fit the structure of a DSC call.
/// callSymbols is expected to begin with the first format specifier, and end with the first EOS symbol.
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
    
    let categoryIndex = formatSpecifier == .allShips ? 2 : 7
    let category = DSCCategory(symbol: callSymbols[categoryIndex])
    
    if(formatSpecifier == .distressAlert) { // Distress Alert is the only call type with this format specifier (112)
        return DistressAlert(callSymbols: callSymbols)
    }
    else if(formatSpecifier == .allShips && category == .distress && DSCFirstTelecommand(symbol: callSymbols[8]) == .distressAcknowledgement) {
        return DistressAcknowledgement(callSymbols: callSymbols)
    }
    else if(category == .distress && DSCFirstTelecommand(symbol: callSymbols[categoryIndex + 6]) == .distressAlertRelay && (eos == .acknowledgementRequired || eos == .other)) {
        return DistressAlertRelay(callSymbols: callSymbols)
    }
    else if(category == .distress && DSCFirstTelecommand(symbol: callSymbols[categoryIndex + 6]) == .distressAlertRelay && eos == .providingAcknowledgement) {
        return DistressAlertRelayAcknowledgement(callSymbols: callSymbols)
    }
    else if(category == .safety || category == .urgency) {
        return UrgencyAndSafetyCall(callSymbols: callSymbols)
    }
    else if(category == .routine) {
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
        guard callSymbols.count >= 17 else {
            print("callSymbols too short for DistressAlert, \(callSymbols.count), need 17.")
            return nil
        }
        
        var currIndex = 2 // Skipping two format specifiers
        
        guard let selfID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlert: Could not parse symbols as MMSI.")
            return nil
        }
        self.selfID = selfID
        currIndex += 5
        
        guard let natureOfDistress = DSCDistressNature(symbol: callSymbols[currIndex]) else {
            print("DistressAlert: Could not parse symbol as DSCDistressNature.")
            return nil
        }
        self.natureOfDistress = natureOfDistress
        currIndex += 1
        
        guard let distressCoordinates = DSCCoordinates(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlert: Could not parse symbols as DSCCoordinates.")
            return nil
        }
        self.distressCoordinates = distressCoordinates
        currIndex += 5
        
        guard let timeUTC = DSCTime(symbols: Array(callSymbols[currIndex..<currIndex+2])) else {
            print("DistressAlert: Could not parse symbols as DSCTime.")
            return nil
        }
        self.timeUTC = timeUTC
        currIndex += 2
        
        self.subsequentCommunications = callSymbols[currIndex]
    }
    
    public var description: String {
        let selfID = selfID.description
        let natureOfDistress = natureOfDistress.description
        let eos = EOS.description
        let distressCoordinates = distressCoordinates.description
        return "\(NSDate().description) - [DISTRESS]: \(selfID) to All Ships - Nature of Distress: \(natureOfDistress) - Coordinates: \(distressCoordinates) - \(eos)"
    }
    
    
}

// Distress Alert Acknowledgements -- Sent by distress alert recipients.
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Category<1> --> Self-ID<5> --> Telecommand<1> --> Distress ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAcknowledgement: DSCCall {
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
        guard callSymbols.count >= 24 else {
            print("callSymbols too short for DistressAcknowledgement, \(callSymbols.count), expected 24.")
            return nil
        }
        
        var currIndex = 3 // Skipping format specifier & hardcoded category
        
        guard let selfID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAcknowledgement: Failed to parse symbols as MMSI.")
            return nil
        }
        self.selfID = selfID
        currIndex += 5
        
        currIndex += 1 // Skipping hardcoded '112' telecommand
        guard let distressID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAcknowledgement: Failed to parse symbols as MMSI.")
            return nil
        }
        self.distressID = distressID
        currIndex += 5
        
        guard let natureOfDistress = DSCDistressNature(symbol: callSymbols[currIndex]) else {
            print("DistressAcknowledgement: Failed to parse symbol as DSCDistressNature.")
            return nil
        }
        self.natureOfDistress = natureOfDistress
        currIndex += 1
        
        guard let distressCoordinates = DSCCoordinates(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAcknowledgement: Failed to parse symbols as CDSCoordinates.")
            return nil
        }
        self.distressCoordinates = distressCoordinates
        currIndex += 5
        
        guard let timeUTC = DSCTime(symbols: Array(callSymbols[currIndex..<currIndex+2])) else {
            print("DistressAcknowledgement: Failed to parse symbols as DSCTime")
            return nil
        }
        self.timeUTC = timeUTC
        currIndex += 2
        
        self.subsequentCommunications = callSymbols[currIndex]
    }
    
    public var description: String {
        let selfID = selfID.description
        let distressID = distressID.description
        let natureOfDistress = natureOfDistress.description
        let eos = EOS.description
        return "\(NSDate().description) - [DISTRESS]: (Distress Acknowledgement) \(selfID) to All Ships - Distress ID: \(distressID) - Nature of Distress: \(natureOfDistress) - Coordinates: \(distressCoordinates) - \(eos)"
    }
}

// Distress Alert Relay
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Address<5> --> Category<1> --> Self-ID<5> --> Telecommand<1> --> Distress ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAlertRelay: DSCCall {
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
    public let distressCoordinates: DSCCoordinates // Message 2
    public let time: DSCTime // Message 3
    public let subsequentCommunications: DSCSymbol // Message 4 -- valid values are 100, 109, 126
    
    init?(callSymbols: [DSCSymbol]) {
        guard callSymbols.count >= 24 else {
            print("callSymbols too short for DistressAlertRelay, got \(callSymbols.count), expected 24 or more.")
            return nil
        }
        var currIndex: Int = 0
        
        guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[currIndex]) else {
            print("DistressAlertRelay: Failed to parse symbol as DSCFormatSpecifier.")
            return nil
        }
        self.formatSpecifier = formatSpecifier
        currIndex += 2
        
        if(formatSpecifier != .allShips) {
            let addressBased: [DSCFormatSpecifier] = [.individualStationSelective, .commonInterestSelective]
            if(addressBased.contains(formatSpecifier)) {
                guard let address = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
                    print("DistressAlertRelay: Failed to parse symbols as MMSI.")
                    return nil
                }
                self.address = address
            }
            else {
                // TODO: Eventually add support for "Area" and "Zone" based addressing here
                self.address = nil
            }
            currIndex += 5
        } else {
            self.address = nil
        }
        
        currIndex += 1 // Skipping Category as it's fixed '112'
        guard let selfID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlertRelay: Failed to parse symbols as MMSI.")
            return nil
        }
        self.selfID = selfID
        currIndex += 5
        
        currIndex += 1 // Skipping 1st telecommand as it's fixed '112'
        guard let distressID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlertRelay: Failed to parse symbols as MMSI.")
            return nil
        }
        self.distressID = distressID
        currIndex += 5
        
        guard let natureOfDistress = DSCDistressNature(symbol: callSymbols[currIndex]) else {
            print("DistressAlertRelay: Failed to parse symbol as DSCDistressNature")
            return nil
        }
        self.natureOfDistress = natureOfDistress
        currIndex += 1
        
        guard let distressCoordinates = DSCCoordinates(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlertRelay: Failed to parse symbols as DSCCoordinates.")
            return nil
        }
        self.distressCoordinates = distressCoordinates
        currIndex += 5
        
        guard let time = DSCTime(symbols: Array(callSymbols[currIndex..<currIndex+2])) else {
            print("DistressAlertRelay: Failed to parse symbols as DSCTime.")
            return nil
        }
        self.time = time
        currIndex += 2
        
        self.subsequentCommunications = callSymbols[currIndex]
        currIndex += 1
        
        guard let EOS = DSCEOSSymbol(symbol: callSymbols[currIndex]) else {
            print("DistressAlertRelay: Invalid EOS Symbol")
            return nil
        }
        self.EOS = EOS
    }
    
    public var description: String {
        let selfID = selfID.description
        let distressID = distressID.description
        let address = address?.description ?? "All Ships / Area"
        let natureOfDistress = natureOfDistress.description
        let eos = EOS.description
        return "\(NSDate().description) - [DISTRESS]: (Distress Alert Relay) \(selfID) to \(address) - Distress ID: \(distressID) - Nature of Distress: \(natureOfDistress) - Coordinates: \(distressCoordinates) - \(eos)"
    }
}

// Distress Alert Relay Acknowledgement
// ---- OTA Format ---- Section<Symbol Count>
// Format Specifier<2 Identical> --> Address<5> --> Category<1> --> Self-ID<5> --> Telecommand<1> --> Distress ID<5> --> Nature of Distress<1> --> Distress Coordinates<5> --> Time<2> --> Subsequent Communications<1>
public struct DistressAlertRelayAcknowledgement: DSCCall {
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
        guard callSymbols.count >= 24 else {
            print("callSymbols too short for DistressAlertRelayAcknowledgement, got \(callSymbols.count), expected 24 or more.")
            return nil
        }
        
        var currIndex = 0
        
        guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[currIndex]) else {
            print("DistressAlertRelayAcknowledgement: Failed to parse symbol as DSCFormatSpecifier.")
            return nil
        }
        self.formatSpecifier = formatSpecifier
        currIndex += 2
        
        if(formatSpecifier != .allShips) {
            let addressBased: [DSCFormatSpecifier] = [.individualStationSelective, .commonInterestSelective]
            if(addressBased.contains(formatSpecifier)) {
                guard let address = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
                    print("DistressAlertRelay: Failed to parse symbols as MMSI.")
                    return nil
                }
                self.address = address
            }
            else {
                // TODO: Eventually add support for "Area" and "Zone" based addressing here
                self.address = nil
            }
            currIndex += 5
        } else {
            self.address = nil
        }
        
        currIndex += 1 // Skipping since Category is hardcoded '112'
        guard let selfID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlertRelay: Failed to parse symbols as MMSI.")
            return nil
        }
        self.selfID = selfID
        currIndex += 5
        
        currIndex += 1 // Skipping 1st telecommand as it's fixed '112'
        guard let distressID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlertRelay: Failed to parse symbols as MMSI.")
            return nil
        }
        self.distressID = distressID
        currIndex += 5
        
        guard let natureOfDistress = DSCDistressNature(symbol: callSymbols[currIndex]) else {
            print("DistressAlertRelay: Failed to parse symbols as MMSI.")
            return nil
        }
        self.natureOfDistress = natureOfDistress
        currIndex += 1
        
        guard let distressCoordinates = DSCCoordinates(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("DistressAlertRelay: Failed to parse symbols as MMSI.")
            return nil
        }
        self.distressCoordinates = distressCoordinates
        currIndex += 5
        
        guard let time = DSCTime(symbols: Array(callSymbols[currIndex..<currIndex+2])) else {
            print("DistressAlertRelay: Failed to parse symbols as DSCTime.")
            return nil
        }
        self.time = time
        currIndex += 2
        
        self.subsequentCommunications = callSymbols[currIndex]
    }
    
    public var description: String {
        let selfID = selfID.description
        let distressID = distressID.description
        let address = address?.description ?? "All Ships / Area"
        let natureOfDistress = natureOfDistress.description
        let eos = EOS.description
        return "\(NSDate().description) - [DISTRESS]: (Distress Alert Relay Acknowledgement) \(selfID) to \(address) - Distress ID: \(distressID) - Nature of Distress: \(natureOfDistress) - Coordinates: \(distressCoordinates) - \(eos)"
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
    public let address: MMSI?
    public let category: DSCCategory // 108 or 110
    public let firstTelecommand: DSCFirstTelecommand // Message 1 (part 1)
    public let secondTelecommand: DSCSecondTelecommand // Message 1 (part 2)
    // Message 2 can be either Frequency or Position -- need to make something for this
    public let time: DSCTime? // Message 3 (Only in position acknowledgements)
    
    init?(callSymbols: [DSCSymbol]) {
        guard callSymbols.count >= 17 else {
            print("callSymbols too short for UrgencyAndSafety (\(callSymbols.count)), expected at least 17.")
            return nil
        }
        
        var currIndex = 0
        guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[currIndex]) else {
            print("First symbol is not a valid format specifier.")
            return nil
        }
        self.formatSpecifier = formatSpecifier
        currIndex += 2
        
        if(formatSpecifier != .allShips) {
            let addressBased: [DSCFormatSpecifier] = [.individualStationSelective, .commonInterestSelective]
            if(addressBased.contains(formatSpecifier)) {
                guard let address = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
                    print("DistressAlertRelay: Failed to parse symbols as MMSI.")
                    return nil
                }
                self.address = address
            }
            else {
                // TODO: Eventually add support for "Area" and "Zone" based addressing here
                self.address = nil
            }
            currIndex += 5
        } else {
            self.address = nil
        }
        
        guard let category = DSCCategory(symbol: callSymbols[currIndex]) else {
            print("Could not parse category symbol.")
            return nil
        }
        guard category == .urgency || category == .safety else {
            print("Invalid category for UrgencyAndSafetyCall: \(category)")
            return nil
        }
        self.category = category
        currIndex += 1
        
        guard let selfID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("Could not parse symbols as MMSI (selfID)")
            return nil
        }
        self.selfID = selfID
        currIndex += 5
        
        guard let firstTelecommand = DSCFirstTelecommand(symbol: callSymbols[currIndex]) else {
            print("Invalid first telecommand: \(callSymbols[currIndex])")
            return nil
        }
        self.firstTelecommand = firstTelecommand
        currIndex += 1
        
        guard let secondTelecommand = DSCSecondTelecommand(symbol: callSymbols[currIndex]) else {
            print("Invalid second telecommand: \(callSymbols[14])")
            return nil
        }
        self.secondTelecommand = secondTelecommand
        currIndex += 1
        
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
        let address = address?.description ?? "All ships"
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
    public let frequency: DSCFrequency? // Message 2
    // Message 2 can be either Frequency or Position -- need to make something for this
    
    init?(callSymbols: [DSCSymbol]) {
        guard callSymbols.count >= 21 else {
            print("callSymbols too short for RoutineCall (\(callSymbols.count)), expected 21-23")
            return nil
        }
        
        var currIndex = 0
        
        guard let formatSpecifier = DSCFormatSpecifier(symbol: callSymbols[currIndex]) else {
            print("First symbol is not a valid format specifier.")
            return nil
        }
        self.formatSpecifier = formatSpecifier
        currIndex += 2 // skipping duplicate format specifier
        
        guard let address = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("Could not parse symbols as MMSI.")
            return nil
        }
        self.address = address
        currIndex += 5
        
        guard let category = DSCCategory(symbol: callSymbols[currIndex]) else {
            print("Could not parse category symbol.")
            return nil
        }
        guard category == .routine else {
            print("Invalid category for RoutineCall: \(category)")
            return nil
        }
        currIndex += 1
        
        guard let selfID = MMSI(symbols: Array(callSymbols[currIndex..<currIndex+5])) else {
            print("Could not parse symbols as MMSI (selfID)")
            return nil
        }
        self.selfID = selfID
        currIndex += 5
        
        guard let firstTelecommand = DSCFirstTelecommand(symbol: callSymbols[currIndex]) else {
            print("Invalid first telecommand for RoutineCall: \(callSymbols[13])")
            return nil
        }
        self.firstTelecommand = firstTelecommand
        currIndex += 1
        
        guard let secondTelecommand = DSCSecondTelecommand(symbol: callSymbols[currIndex]) else {
            print("Invalid second telecommand for RoutineCall: \(callSymbols[14])")
            return nil
        }
        self.secondTelecommand = secondTelecommand
        currIndex += 1
        
        if callSymbols[currIndex].symbol == 4 {
            guard callSymbols.count > 23 else {
                print("RoutineCall has 4-symbol frequency specified, but length is too short (\(callSymbols.count).")
                return nil
            }
            self.frequency = DSCFrequency(symbols: Array(callSymbols[currIndex..<currIndex+8]))
        } else {
            self.frequency = DSCFrequency(symbols: Array(callSymbols[currIndex..<currIndex+6]))
        }
        
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
        let frequencyString = self.frequency?.description ?? "No Frequency"
        return "\(NSDate().description) - [ROUTINE]: \(selfID) to \(address) - 1st Command: \(commandOne) 2nd Command: \(commandTwo) - \(frequencyString) - \(eos)"
    }
}
