//
//  DSCSymbolEnums.swift
//  SwiftDSC
//
//  Created by Connor Gibbons  on 9/19/25.
//
//  Contains symbol meanings in the context of various DSC structures.

// Format specifier is sent twice consecutively in every call. Determines the structure of the message to follow.
public enum DSCFormatSpecifier: UInt8 {
    case geographicalSelective = 102
    case distressAlert = 112
    case commonInterestSelective = 114
    case allShips = 116
    case individualStationSelective = 120
    case nationalNonCallingReserved = 121
    case automaticServiceSelective = 123
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .geographicalSelective:
            return "Geographical area call"
        case .distressAlert:
            return "Distress alert"
        case .commonInterestSelective:
            return "Common interest group call"
        case .allShips:
            return "All ships call"
        case .individualStationSelective:
            return "Individual station call"
        case .nationalNonCallingReserved:
            return "National use (non-calling) / Reserved"
        case .automaticServiceSelective:
            return "Automatic service call"
        }
    }
}

// Category is sent once, only in specific call formats. It describes the "degree of priority" of the call.
public enum DSCCategory: UInt8 {
    case routine = 100
    case safety = 108
    case urgency = 110
    case distress = 112
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .routine:
            return "Routine"
        case .safety:
            return "Safety"
        case .urgency:
            return "Urgency"
        case .distress:
            return "Distress"
        }
    }
}

public enum DSCEOSSymbol: UInt8 {
    case acknowledgementRequired = 117 // "Ack. RQ"
    case providingAcknowledgement = 122 // Couldn't think of a better name for this -- it means the message is an answer to a call requiring acknowledgement. ("Ack. BQ")
    case other = 127
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .acknowledgementRequired:
            return "Ack. Required"
        case .providingAcknowledgement:
            return "Providing Ack."
        case .other:
            return "Other"
        }
    }
}

// Nature of Distress is only present in certain message types like Distress Alert (112) and Distress Acnkowledgement (116).
public enum DSCDistressNature: UInt8 {
    case fire = 100
    case flooding = 101
    case collision = 102
    case grounding = 103
    case listing = 104
    case sinking = 105
    case disabled = 106
    case undesignated = 107
    case abandoningShip = 108
    case piracyOrRobbery = 109
    case manOverboard = 110
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .fire:
            return "Fire/Explosion"
        case .flooding:
            return "Flooding"
        case .collision:
            return "Collision"
        case .grounding:
            return "Grounding"
        case .listing:
            return "Listing (Loss of stability)"
        case .sinking:
            return "Sinking"
        case .disabled:
            return "Disabled and adrift"
        case .undesignated:
            return "Undesignated distress"
        case .abandoningShip:
            return "Abandoning ship"
        case .piracyOrRobbery:
            return "Piracy/Armed robbery attack"
        case .manOverboard:
            return "Man overboard"
        }
    }
}

// This is what the spec refers to this grouping as, whether it really is a "command" is context dependent.
public enum DSCFirstTelecommand: UInt8 {
    case fmTelephony = 100 // "F3E/G3E All modes TP"
    case fmTelephonyDuplex = 101 // "F3E/G3E duplex TP"
    case polling = 103
    case unableToComply = 104
    case endOfCall = 105 // Footing says "only used for Automatic service"
    case data = 106
    case ssbTelephony = 109 // "J3E TP"
    case distressAcknowledgement = 110
    case distressAlertRelay = 112
    case ssbTTYForwardErrorCorrecting = 113 // F1B/J2B TTY-FEC
    case ssbTTYAutoRepeat = 115 // F1B/J2B TTY-ARQ (Automatic Repeat reQuest)
    case test = 118
    case shipPositionUpdating = 121 // "Ship position or location registration updating"
    case noInformation = 126
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .fmTelephony:
            return "VHF FM Telephony"
        case .fmTelephonyDuplex:
            return "VHF FM Telephony (Duplex)"
        case .polling:
            return "Polling"
        case .unableToComply:
            return "Unable to comply"
        case .endOfCall:
            return "End of Call"
        case .data:
            return "Data"
        case .ssbTelephony:
            return "SSB Telephony (J3E TP)"
        case .distressAcknowledgement:
            return "Distress Acknowledgement"
        case .distressAlertRelay:
            return "Distress Alert Relay"
        case .ssbTTYForwardErrorCorrecting:
            return "F1B/J2B TTY-FEC"
        case .ssbTTYAutoRepeat:
            return "F1B/J2B TTY-ARQ"
        case .test:
            return "Test"
        case .shipPositionUpdating:
            return "Ship position or location registration updating"
        case .noInformation:
            return "No information"
        }
    }
}

public enum DSCSecondTelecommand: UInt8 {
    case noReasonGiven = 100
    case congestion = 101 // "Congestion at maritime switching centre"
    case busy = 102
    case queueIndication = 103
    case stationBarred = 104
    case noOperator = 105 // "No operator available"
    case operatorUnavailable = 106 // "Operator temporarily unavailable"
    case equipmentDisabled = 107
    case channelUnusable = 108 // "Unable to use proposed channel"
    case modeUnusable = 109 // "Unable to use proposed mode"
    case nonArmedConflict = 110 // "Ships and aircraft of States not parties to an armed conflict" ????
    case medicalTransports = 111 // "Medical transports (as defined in 1949 Geneva Conventions and additional Protocols)"
    case publicPhone = 112 // "Pay-phone/public call office"
    case facsimile = 113
    case noRemainingACSSequentialTransmission = 120 // No idea what these mean.
    case oneRemainingACSSequentialTransmission = 121
    case twoRemainingACSsequentialTransmission = 122
    case threeRemainingACSSequentialTransmission = 123
    case fourRemainingACSSequentialTransmission = 124
    case fiveRemainingACSSequentialTransmission = 125
    case noInformation = 126
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .noReasonGiven:
            return "No reason given"
        case .congestion:
            return "Congestion at maritime switching centre"
        case .busy:
            return "Busy"
        case .queueIndication:
            return "Queue indication"
        case .stationBarred:
            return "Station barred"
        case .noOperator:
            return "No operator available"
        case .operatorUnavailable:
            return "Operator temporarily unavailable"
        case .equipmentDisabled:
            return "Equipment disabled"
        case .channelUnusable:
            return "Unable to use proposed channel"
        case .modeUnusable:
            return "Unable to use proposed mode"
        case .nonArmedConflict:
            return "Ships/aircraft of States not parties to an armed conflict"
        case .medicalTransports:
            return "Medical transports (per 1949 Geneva Conventions)"
        case .publicPhone:
            return "Pay-phone / public call office"
        case .facsimile:
            return "Facsimile"
        case .noRemainingACSSequentialTransmission:
            return "No remaining ACS sequential transmission"
        case .oneRemainingACSSequentialTransmission:
            return "One remaining ACS sequential transmission"
        case .twoRemainingACSsequentialTransmission:
            return "Two remaining ACS sequential transmissions"
        case .threeRemainingACSSequentialTransmission:
            return "Three remaining ACS sequential transmissions"
        case .fourRemainingACSSequentialTransmission:
            return "Four remaining ACS sequential transmissions"
        case .fiveRemainingACSSequentialTransmission:
            return "Five remaining ACS sequential transmissions"
        case .noInformation:
            return "No information"
        }
    }
}

// Used within the coordinates structure (DSCCoordinates)
public enum DSCQuadrant: UInt8 {
    case NE = 0
    case NW = 1
    case SE = 2
    case SW = 3
    case missing = 99
    
    init?(symbol: DSCSymbol) {
        guard let raw = symbol.symbol else { return nil }
        self.init(rawValue: raw)
    }
    
    var description: String {
        switch self {
        case .NE:
            return "NE"
        case .NW:
            return "NW"
        case .SE:
            return "SE"
        case .SW:
            return "SW"
        case .missing:
            return "Missing"
        }
    }
}
